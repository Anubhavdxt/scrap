import Foundation
import ServiceManagement

/// Login item for the app bundle, via the system's ServiceManagement API.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// What to tell the user after they switched it on or off, given where the system left things.
    static func message(requested: Bool, status: SMAppService.Status) -> String {
        switch (requested, status) {
        case (_, .requiresApproval): "Approve scrap in System Settings → General → Login Items."
        case (true, .enabled): "scrap will open when you log in."
        case (true, _): "Couldn't turn it on. This only works for the installed Scrap.app."
        case (false, .enabled): "Couldn't turn it off. Do it in System Settings → General → Login Items."
        case (false, _): "scrap won't open at login."
        }
    }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
