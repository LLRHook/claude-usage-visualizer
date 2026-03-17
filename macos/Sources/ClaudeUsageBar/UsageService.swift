import Foundation
import AppKit
import CryptoKit

@MainActor
final class UsageService: ObservableObject {
    // MARK: - OAuth Constants

    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let authorizeURL = "https://claude.ai/oauth/authorize"
    private let tokenURL = "https://platform.claude.com/v1/oauth/token"
    private let redirectURI = "https://platform.claude.com/oauth/code/callback"
    private let scopes = "user:profile user:inference"
    private let betaHeader = "oauth-2025-04-20"

    #if DEBUG
    private var baseURL: String {
        ProcessInfo.processInfo.environment["CLAUDE_USAGE_BASE_URL"] ?? "https://api.anthropic.com"
    }
    #else
    private let baseURL = "https://api.anthropic.com"
    #endif

    // MARK: - Published State

    @Published var isAuthenticated = false
    @Published var isAwaitingCode = false
    @Published var lastError: String?
    @Published var accountEmail: String?
    @Published var currentUsage: UsageResponse?
    @Published var lastUpdated: Date?
    @Published var pollingInterval: TimeInterval = 1800 // 30 min default

    // MARK: - Private State

    private var codeVerifier: String?
    private var oauthState: String?
    private var credentials: StoredCredentials?
    private var isRefreshing = false
    private var pollingTask: Task<Void, Never>?
    private var currentBackoff: TimeInterval = 0
    private var previousUsage: UsageResponse?

    weak var historyService: UsageHistoryService?

    private let store = StoredCredentialsStore.shared

    // MARK: - Lifecycle

    func loadCredentials() {
        if let creds = store.load() {
            credentials = creds
            isAuthenticated = true
            startPolling()
            Task { await fetchProfile() }
            Task { await fetchUsage() }
        }
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() {
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateCodeVerifier()
        oauthState = state

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code", value: "true"),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
            isAwaitingCode = true
            lastError = nil
        }
    }

    func submitOAuthCode(_ rawInput: String) async {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "#", maxSplits: 1)
        let code = String(parts[0])

        if parts.count > 1 {
            let returnedState = String(parts[1])
            guard returnedState == oauthState else {
                lastError = "OAuth state mismatch — try again"
                isAwaitingCode = false
                codeVerifier = nil
                oauthState = nil
                return
            }
        }

        await exchangeCodeForTokens(code: code)
    }

    func signOut() {
        credentials = nil
        isAuthenticated = false
        isAwaitingCode = false
        accountEmail = nil
        currentUsage = nil
        lastUpdated = nil
        previousUsage = nil
        lastError = nil
        pollingTask?.cancel()
        pollingTask = nil
        store.delete()
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String) async {
        guard let verifier = codeVerifier else {
            lastError = "Missing code verifier."
            return
        }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": oauthState ?? "",
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]

        do {
            let creds = try await performTokenRequest(body: body)
            credentials = creds
            try store.save(creds)
            isAuthenticated = true
            isAwaitingCode = false
            codeVerifier = nil
            oauthState = nil
            lastError = nil
            startPolling()
            Task { await fetchProfile() }
            Task { await fetchUsage() }
        } catch {
            lastError = "Token exchange failed: \(error.localizedDescription)"
        }
    }

    func refreshTokenIfNeeded() async -> Bool {
        guard let creds = credentials, creds.needsRefresh() else { return true }
        guard let refreshToken = creds.refreshToken, !isRefreshing else { return false }

        isRefreshing = true
        defer { isRefreshing = false }

        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        if !creds.scopes.isEmpty {
            body["scope"] = creds.scopes.joined(separator: " ")
        }

        do {
            let newCreds = try await performTokenRequest(body: body)
            credentials = newCreds
            try store.save(newCreds)
            return true
        } catch {
            return false
        }
    }

    private func performTokenRequest(body: [String: String]) async throws -> StoredCredentials {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "TokenExchange", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(errorBody)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw NSError(domain: "TokenExchange", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Missing access_token in response"])
        }

        let scopes = (json["scope"] as? String)?
            .split(whereSeparator: \.isWhitespace).map(String.init)
            ?? Self.defaultScopes

        var expiresAt: Date?
        if let expiresIn = json["expires_in"] as? Int {
            expiresAt = Date().addingTimeInterval(Double(expiresIn))
        } else if let expiresIn = json["expires_in"] as? Double {
            expiresAt = Date().addingTimeInterval(expiresIn)
        }

        return StoredCredentials(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: expiresAt,
            scopes: scopes
        )
    }

    private static let defaultScopes = ["user:profile", "user:inference"]

    // MARK: - API Requests

    func fetchUsage() async {
        guard let creds = credentials else { return }

        guard await refreshTokenIfNeeded() else {
            signOut()
            return
        }

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/oauth/usage")!)
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            switch http.statusCode {
            case 200:
                let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
                currentUsage = usage.reconciled(with: previousUsage)
                previousUsage = currentUsage
                lastUpdated = Date()
                lastError = nil
                currentBackoff = 0

                // Record history
                if let fiveHour = currentUsage?.fiveHour, let sevenDay = currentUsage?.sevenDay {
                    historyService?.recordDataPoint(
                        pct5h: fiveHour.fraction,
                        pct7d: sevenDay.fraction
                    )
                }

            case 401:
                if await refreshTokenIfNeeded() {
                    // Retry once with new token
                    await fetchUsage()
                } else {
                    signOut()
                }

            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? 60
                currentBackoff = min(max(currentBackoff * 2, retryAfter), 3600)
                lastError = "Rate limited. Retrying in \(Int(currentBackoff))s."

            default:
                lastError = "API error: HTTP \(http.statusCode)"
            }
        } catch {
            lastError = "Network error: \(error.localizedDescription)"
        }
    }

    private func fetchProfile() async {
        guard let creds = credentials else { return }

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/oauth/userinfo")!)
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            struct UserInfo: Codable {
                let email: String?
            }
            let info = try JSONDecoder().decode(UserInfo.self, from: data)
            accountEmail = info.email
        } catch {
            // Non-critical — silently ignore
        }
    }

    // MARK: - Polling

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let delay = self.currentBackoff > 0 ? self.currentBackoff : self.pollingInterval
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { break }
                await self.fetchUsage()
            }
        }
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
