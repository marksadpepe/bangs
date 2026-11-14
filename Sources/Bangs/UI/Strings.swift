import Foundation

/// Тексты интерфейса на двух языках (из `renderVals()` → `S`).
struct Strings {
    let openPanel, collapse: String
    let done, wait, seen, working: String
    let justNow, workingJustNow, waitingJustNow: String
    let waitSeen, denied: String
    let nDone, nWait, nWork, quiet, completed, allSeen: String
    let markAll, settings, back, backToChats, theme, language, dark, light: String
    let doneColor, waitColor, reset, quit: String
    let min, hour, ago, waits: String
    let lastMsg, openTerminal, askPerm, askQ, askGeneric, askTool, replyInTerminal: String
    let optYes, optAlways, optNo: String
    let jumpOnClick, launchAtLogin: String
    let empty: String

    func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)\(min)" : "\(minutes / 60)\(hour)"
    }

    static let ru = Strings(
        openPanel: "Открыть панель Claude Code", collapse: "Свернуть панель",
        done: "Готово", wait: "Ждёт тебя", seen: "просмотрено", working: "работает",
        justNow: "только что", workingJustNow: "работает · только что", waitingJustNow: "ждёт · только что",
        waitSeen: "видел · ждёт ответа", denied: "отклонено · ответь в терминале",
        nDone: " готово", nWait: " ждёт", nWork: " в работе", quiet: "тихо",
        completed: " завершено", allSeen: "всё просмотрено",
        markAll: "Отметить всё просмотренным", settings: "Настройки", back: "Назад",
        backToChats: "К чатам", theme: "Тема", language: "Язык", dark: "Тёмная", light: "Светлая",
        doneColor: "Цвет «готово»", waitColor: "Цвет «ждёт»", reset: "Сбросить цвета", quit: "Выйти",
        min: " мин", hour: " ч", ago: " назад", waits: "ждёт ",
        lastMsg: "Последнее сообщение", openTerminal: "Открыть в терминале",
        askPerm: "Хочет выполнить команду", askQ: "Задаёт вопрос", askGeneric: "Ждёт ответа",
        askTool: "Просит разрешение · ",
        replyInTerminal: "Ответить можно в терминале",
        optYes: "Да", optAlways: "Да, и больше не спрашивать", optNo: "Нет",
        jumpOnClick: "Клик по чату — в терминал", launchAtLogin: "Запускать при входе",
        empty: "Нет активных чатов")

    static let en = Strings(
        openPanel: "Open Claude Code panel", collapse: "Collapse panel",
        done: "Done", wait: "Needs you", seen: "seen", working: "working",
        justNow: "just now", workingJustNow: "working · just now", waitingJustNow: "waiting · just now",
        waitSeen: "seen · still waiting", denied: "denied · reply in terminal",
        nDone: " done", nWait: " waiting", nWork: " running", quiet: "quiet",
        completed: " finished", allSeen: "all seen",
        markAll: "Mark all as seen", settings: "Settings", back: "Back",
        backToChats: "Back to chats", theme: "Theme", language: "Language", dark: "Dark", light: "Light",
        doneColor: "“Done” color", waitColor: "“Waiting” color", reset: "Reset colors", quit: "Quit",
        min: " min", hour: " h", ago: " ago", waits: "waiting ",
        lastMsg: "Last message", openTerminal: "Open in terminal",
        askPerm: "Wants to run a command", askQ: "Has a question", askGeneric: "Needs your input",
        askTool: "Needs permission · ",
        replyInTerminal: "Reply in the terminal",
        optYes: "Yes", optAlways: "Yes, and don’t ask again", optNo: "No",
        jumpOnClick: "Click opens terminal", launchAtLogin: "Launch at login",
        empty: "No active chats")
}
