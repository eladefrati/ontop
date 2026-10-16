import os

/// Log interpolations of window titles, frames and errors are marked `privacy: .public` so
/// they are readable in `make log` during development. TODO: drop the `privacy: .public`
/// arguments (back to the redacting default) when development is done.
enum Log {
    static let subsystem = "io.github.eladefrati.ontop"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let target = Logger(subsystem: subsystem, category: "target")
    static let mirror = Logger(subsystem: subsystem, category: "mirror")
}
