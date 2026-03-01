import OSLog

struct Log {
    // A logger with our app's bundle id and a "general" category.
    static let general = Logger(subsystem: "com.glowberrylabs.speakeasy", category: "general")
}
