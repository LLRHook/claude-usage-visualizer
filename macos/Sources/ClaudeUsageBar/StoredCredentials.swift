import Foundation

struct StoredCredentials: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scopes: [String]

    func needsRefresh(leeway: TimeInterval = 60) -> Bool {
        guard let refreshToken, !refreshToken.isEmpty,
              let expiresAt else { return false }
        return Date().addingTimeInterval(leeway) >= expiresAt
    }
}

final class StoredCredentialsStore: Sendable {
    static let shared = StoredCredentialsStore()

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/claude-usage-bar")
    }()

    private var credentialsFile: URL {
        configDir.appendingPathComponent("credentials.json")
    }

    private var legacyTokenFile: URL {
        configDir.appendingPathComponent("token")
    }

    func load() -> StoredCredentials? {
        // Try credentials.json first
        if let data = try? Data(contentsOf: credentialsFile),
           let creds = try? JSONDecoder.iso8601Decoder.decode(StoredCredentials.self, from: data) {
            return creds
        }
        // Fall back to legacy token file
        if let tokenData = try? Data(contentsOf: legacyTokenFile),
           let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return StoredCredentials(accessToken: token, refreshToken: nil, expiresAt: nil, scopes: [])
        }
        return nil
    }

    func save(_ credentials: StoredCredentials) throws {
        try ensureConfigDir()
        let data = try JSONEncoder.iso8601Encoder.encode(credentials)
        try data.write(to: credentialsFile, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: credentialsFile.path
        )
    }

    func delete() {
        try? FileManager.default.removeItem(at: credentialsFile)
    }

    private func ensureConfigDir() throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: configDir.path, isDirectory: &isDir) {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: configDir.path
            )
        }
    }
}

extension JSONDecoder {
    static let iso8601Decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso8601Encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
