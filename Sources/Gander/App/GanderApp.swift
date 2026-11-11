import AppKit

@main
@MainActor
enum GanderApp {
    static func main() {
        let options = LaunchOptions.parse(CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
        let delegate = AppDelegate(options: options)
        let app = NSApplication.shared
        app.delegate = delegate
        // A menu bar utility: no Dock icon, never the frontmost app.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
