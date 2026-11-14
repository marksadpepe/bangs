import Foundation
import Observation

enum ThemeMode: String, CaseIterable { case dark, light }
enum Lang: String, CaseIterable { case ru, en }

/// Настройки панели. Хранятся в UserDefaults (без него — только в памяти, для превью).
@Observable
final class AppSettings {
    static let defaultDone = "#FF8A3D"
    static let defaultWait = "#5AA2FF"
    static let donePalette = ["#FF8A3D", "#34C759", "#FFD60A", "#FF5E7E", "#BF5AF2"]
    static let waitPalette = ["#5AA2FF", "#64D2FF", "#BF5AF2", "#FFD60A", "#FF5E7E"]

    @ObservationIgnored private let defaults: UserDefaults?

    var theme: ThemeMode { didSet { defaults?.set(theme.rawValue, forKey: Keys.theme) } }
    var lang: Lang { didSet { defaults?.set(lang.rawValue, forKey: Keys.lang) } }
    var doneColor: String { didSet { defaults?.set(doneColor, forKey: Keys.done) } }
    var waitColor: String { didSet { defaults?.set(waitColor, forKey: Keys.wait) } }
    /// Клик по готовому/работающему чату переключает на его вкладку в Terminal.
    var jumpOnClick: Bool { didSet { defaults?.set(jumpOnClick, forKey: Keys.jump) } }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        let systemLang: Lang = (Locale.preferredLanguages.first ?? "ru").hasPrefix("ru") ? .ru : .en
        theme = ThemeMode(rawValue: defaults?.string(forKey: Keys.theme) ?? "") ?? .dark
        lang = Lang(rawValue: defaults?.string(forKey: Keys.lang) ?? "") ?? systemLang
        doneColor = defaults?.string(forKey: Keys.done) ?? Self.defaultDone
        waitColor = defaults?.string(forKey: Keys.wait) ?? Self.defaultWait
        jumpOnClick = defaults?.object(forKey: Keys.jump) as? Bool ?? true
    }

    func resetColors() {
        doneColor = Self.defaultDone
        waitColor = Self.defaultWait
    }

    private enum Keys {
        static let theme = "theme"
        static let lang = "lang"
        static let done = "doneColor"
        static let wait = "waitColor"
        static let jump = "jumpOnClick"
    }
}
