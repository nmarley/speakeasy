enum Version {
    static let current = "1.2.2"

    #if DEBUG
        static let suffix = "-dev"
    #else
        static let suffix = ""
    #endif

    static var full: String {
        return current + suffix
    }
}
