import Foundation
import ServiceManagement

/// Автозапуск при входе в систему через SMAppService (регистрирует тот бандл, из которого запущено приложение).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Bangs: не удалось изменить автозапуск: \(error)")
        }
        return isEnabled
    }
}
