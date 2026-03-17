#!/usr/bin/env python3
"""Mock server for Claude Usage Bar development.

Usage:
    python3 scripts/mock-server.py

Switch scenarios at runtime:
    curl http://localhost:7891/scenario/high
"""

import json
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

SCENARIOS = {
    "normal": {
        "five_hour": {"utilization": 25.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 40.0, "resets_at": "2025-06-20T00:00:00Z"},
    },
    "low": {
        "five_hour": {"utilization": 5.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 10.0, "resets_at": "2025-06-20T00:00:00Z"},
    },
    "medium": {
        "five_hour": {"utilization": 55.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 65.0, "resets_at": "2025-06-20T00:00:00Z"},
    },
    "high": {
        "five_hour": {"utilization": 82.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 90.0, "resets_at": "2025-06-20T00:00:00Z"},
    },
    "maxed": {
        "five_hour": {"utilization": 100.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 100.0, "resets_at": "2025-06-20T00:00:00Z"},
    },
    "extra": {
        "five_hour": {"utilization": 70.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 85.0, "resets_at": "2025-06-20T00:00:00Z"},
        "extra_usage": {
            "is_enabled": True,
            "utilization": 30.0,
            "used_credits": 600,
            "monthly_limit": 2000,
        },
    },
    "per_model": {
        "five_hour": {"utilization": 50.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 60.0, "resets_at": "2025-06-20T00:00:00Z"},
        "seven_day_opus": {"utilization": 80.0, "resets_at": "2025-06-20T00:00:00Z"},
        "seven_day_sonnet": {"utilization": 40.0, "resets_at": "2025-06-20T00:00:00Z"},
    },
    "all_features": {
        "five_hour": {"utilization": 65.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 75.0, "resets_at": "2025-06-20T00:00:00Z"},
        "seven_day_opus": {"utilization": 90.0, "resets_at": "2025-06-20T00:00:00Z"},
        "seven_day_sonnet": {"utilization": 55.0, "resets_at": "2025-06-20T00:00:00Z"},
        "extra_usage": {
            "is_enabled": True,
            "utilization": 45.0,
            "used_credits": 900,
            "monthly_limit": 2000,
        },
    },
    "zero": {
        "five_hour": {"utilization": 0.0, "resets_at": "2025-06-15T14:00:00Z"},
        "seven_day": {"utilization": 0.0, "resets_at": "2025-06-20T00:00:00Z"},
    },
    "unauthenticated": None,  # 401
    "rate_limited": None,  # 429
    "error": None,  # 500
    "slow": "slow",  # 5s delay then normal
}

current_scenario = "normal"


class MockHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global current_scenario

        # Scenario switching
        if self.path.startswith("/scenario/"):
            name = self.path.split("/scenario/")[1]
            if name in SCENARIOS:
                current_scenario = name
                self._json_response(200, {"scenario": name, "status": "active"})
            else:
                self._json_response(404, {"error": f"Unknown scenario: {name}", "available": list(SCENARIOS.keys())})
            return

        # Usage endpoint
        if self.path == "/api/oauth/usage":
            if current_scenario == "unauthenticated":
                self._json_response(401, {"error": "Unauthorized"})
                return
            if current_scenario == "rate_limited":
                self.send_response(429)
                self.send_header("Content-Type", "application/json")
                self.send_header("Retry-After", "30")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Rate limited"}).encode())
                return
            if current_scenario == "error":
                self._json_response(500, {"error": "Internal server error"})
                return
            if current_scenario == "slow":
                time.sleep(5)
                self._json_response(200, SCENARIOS["normal"])
                return

            data = SCENARIOS.get(current_scenario, SCENARIOS["normal"])
            self._json_response(200, data)
            return

        # Userinfo endpoint
        if self.path == "/api/oauth/userinfo":
            if current_scenario == "unauthenticated":
                self._json_response(401, {"error": "Unauthorized"})
                return
            self._json_response(200, {"email": "test@example.com", "name": "Test User"})
            return

        self._json_response(404, {"error": "Not found"})

    def do_POST(self):
        # Token endpoint
        if self.path == "/v1/oauth/token":
            self._json_response(200, {
                "access_token": "mock_access_token_12345",
                "refresh_token": "mock_refresh_token_67890",
                "expires_in": 3600,
                "scope": "user:profile user:inference",
            })
            return

        self._json_response(404, {"error": "Not found"})

    def _json_response(self, status, data):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        print(f"[{current_scenario}] {format % args}")


if __name__ == "__main__":
    server = HTTPServer(("localhost", 7891), MockHandler)
    print(f"Mock server running on http://localhost:7891")
    print(f"Current scenario: {current_scenario}")
    print(f"Switch: curl http://localhost:7891/scenario/<name>")
    print(f"Available: {', '.join(SCENARIOS.keys())}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()
