import OSLog

struct Log {
    // A logger with our app's bundle id and a "general" category.
    static let general = Logger(subsystem: "com.glowberrylabs.speakeasy", category: "general")

    // Cleanup outcomes land in their own category so transcript
    // cleanup can be inspected with:
    // log show --predicate 'subsystem == "com.glowberrylabs.speakeasy" && category == "cleanup"'
    static let cleanup = Logger(subsystem: "com.glowberrylabs.speakeasy", category: "cleanup")
}
