import Foundation
import ServiceManagement

/// "Launch at login", so the menu bar icon comes back after a restart.
enum LoginItem {
    private static let autoEnabledKey = "didAutoEnableLoginItem"

    /// Only an app in /Applications or ~/Applications is registered, so the login
    /// item never points at a build folder that may be deleted or rebuilt.
    static var isInstalledLocation: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }
    static var needsApproval: Bool { status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Turns launch at login on the first time the installed app runs. After that
    /// the settings toggle decides, and turning it off sticks.
    static func enableOnFirstRun() {
        let defaults = UserDefaults.standard
        guard isInstalledLocation, !defaults.bool(forKey: autoEnabledKey) else { return }
        defaults.set(true, forKey: autoEnabledKey)
        if status != .enabled { try? SMAppService.mainApp.register() }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
