import os

/// Interpolated strings are redacted as <private> by the unified logging default; integers
/// and other scalars are public. For a readable `make log` during debugging, add
/// `privacy: .public` to the string interpolations you need and revert before committing.
enum Log {
    static let subsystem = "io.github.eladefrati.ontop"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let target = Logger(subsystem: subsystem, category: "target")
    static let mirror = Logger(subsystem: subsystem, category: "mirror")
}
