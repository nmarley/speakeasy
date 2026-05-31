enum Version {
    static let current = "1.0.1"

    #if DEBUG
        static let suffix = "-dev"
    #else
        static let suffix = ""
    #endif

    static var full: String {
        return current + suffix
    }
}
