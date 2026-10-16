import os

/// Interpolated values use the unified logging default, which redacts them as <private>.
/// For a readable `make log` during debugging, add `privacy: .public` to the
/// interpolations you need and revert before committing.
enum Log {
    static let subsystem = "io.github.eladefrati.ontop"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let target = Logger(subsystem: subsystem, category: "target")
    static let mirror = Logger(subsystem: subsystem, category: "mirror")
}
