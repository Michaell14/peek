import Foundation

/// Command-line switches, mostly for development and automated checks.
struct LaunchOptions {
    /// Where the workspace is stored; defaults to Application Support.
    var dataDirectory: URL?
    /// Run the self-check, write its report into this directory, and quit.
    var smokeTestOutput: URL?
    /// Open the overlay as soon as the app has started.
    var showOnLaunch = false

    static func parse(_ arguments: [String], environment: [String: String]) -> LaunchOptions {
        var options = LaunchOptions()
        if let path = environment["BLICK_DATA_DIR"], !path.isEmpty {
            options.dataDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            let value = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch argument {
            case "--data-dir":
                if let value {
                    options.dataDirectory = URL(fileURLWithPath: value, isDirectory: true)
                    index += 1
                }
            case "--smoke-test":
                if let value {
                    options.smokeTestOutput = URL(fileURLWithPath: value, isDirectory: true)
                    index += 1
                }
            case "--show":
                options.showOnLaunch = true
            default:
                break
            }
            index += 1
        }
        return options
    }
}
