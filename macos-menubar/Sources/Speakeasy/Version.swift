enum Version {
    static let current = "0.6.6"

    #if DEBUG
        static let suffix = "-dev"
    #else
        static let suffix = ""
    #endif

    static var full: String {
        return current + suffix
    }
}
