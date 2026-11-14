import Foundation

/// Моковые данные из дизайна (Main.dc.html → renderVals → data).
enum MockData {
    static let account = Account(name: "Alex", email: "alex@example.com")

    static func chats(lang: Lang, now: Date = Date()) -> [Chat] {
        let ru = lang == .ru
        let home = NSHomeDirectory()
        func ago(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }

        let api = home + "/work/api-server"
        let landing = home + "/work/landing"
        let dotfiles = home + "/dotfiles"

        return [
            Chat(id: "a1", title: ru ? "Миграция на Postgres 16" : "Migrate to Postgres 16",
                 cwd: api, status: .done, statusSince: ago(1)),
            Chat(id: "a2", title: ru ? "Покрыть тестами auth-модуль" : "Cover auth module with tests",
                 cwd: api, status: .working, statusSince: ago(6)),
            Chat(id: "b1", title: ru ? "Адаптив для мобилки" : "Mobile responsive layout",
                 cwd: landing, status: .done, statusSince: ago(4)),
            Chat(id: "b2", title: ru ? "Обновить зависимости" : "Update dependencies",
                 cwd: landing, status: .waiting, statusSince: ago(3),
                 request: PendingRequest(
                    kind: .permission,
                    context: ru
                        ? "Обновил package.json: next 14 → 15 и react 18 → 19. Теперь нужно поставить зависимости и прогнать тесты, чтобы проверить, что сборка не сломалась."
                        : "Bumped package.json: next 14 → 15 and react 18 → 19. Now I need to install dependencies and run the tests to make sure the build still works.",
                    command: "pnpm install && pnpm test",
                    options: ru
                        ? ["Да", "Да, и не спрашивать про pnpm в этом проекте", "Нет"]
                        : ["Yes", "Yes, and don’t ask again for pnpm in this project", "No"])),
            Chat(id: "c2", title: ru ? "Перевести плагины на менеджер" : "Move plugins to a manager",
                 cwd: dotfiles, status: .waiting, statusSince: ago(9),
                 request: PendingRequest(
                    kind: .question,
                    context: ru
                        ? "Нашёл в .zshrc ручную загрузку шести плагинов. Если перевести их на менеджер, оболочка будет стартовать быстрее."
                        : "Found six plugins loaded by hand in .zshrc. Moving them to a plugin manager would make the shell start faster.",
                    question: ru ? "Какой менеджер плагинов использовать?" : "Which plugin manager should I use?",
                    options: ru
                        ? ["zinit — быстрый, много настроек", "antidote — проще, статичная загрузка", "Оставить как есть"]
                        : ["zinit — fast, lots of options", "antidote — simpler, static loading", "Keep it as is"])),
            Chat(id: "c1", title: ru ? "Настроить плагины zsh" : "Set up zsh plugins",
                 cwd: dotfiles, status: .seen, statusSince: ago(22)),
        ]
    }
}
