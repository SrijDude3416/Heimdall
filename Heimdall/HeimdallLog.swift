import os

enum HeimdallLog {
    static let auth = Logger(subsystem: "com.srija.Heimdall", category: "auth")
    static let lock = Logger(subsystem: "com.srija.Heimdall", category: "lock")
}
