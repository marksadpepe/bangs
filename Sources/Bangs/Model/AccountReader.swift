import Foundation

/// Имя и почта аккаунта Claude Code из `.claude.json` (блок `oauthAccount`).
enum AccountReader {
    static let defaultConfigDir = NSHomeDirectory() + "/.claude"

    /// Для `~/.claude` файл лежит в `~/.claude.json`, для своего CLAUDE_CONFIG_DIR — внутри него.
    static func read(configDir: String?) -> Account? {
        let dir = configDir ?? defaultConfigDir
        let path = dir == defaultConfigDir ? NSHomeDirectory() + "/.claude.json" : dir + "/.claude.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["oauthAccount"] as? [String: Any] else { return nil }

        func field(_ key: String) -> String? {
            guard let s = oauth[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        let email = field("emailAddress")
        guard let name = field("displayName") ?? field("fullName") ?? email else { return nil }
        let full = field("fullName")
        return Account(name: name, email: email, fullName: full != name ? full : nil)
    }
}
