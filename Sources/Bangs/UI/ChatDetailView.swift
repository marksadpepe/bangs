import SwiftUI

/// Экран ожидающего чата: последнее сообщение, запрос, варианты ответа, «Открыть в терминале».
/// v1: ответ из панели не поддерживается — варианты показаны неактивными.
struct ChatDetailView: View {
    let model: AppModel
    let chat: Chat

    var body: some View {
        let pal = model.palette
        let s = model.strings
        let wait = model.waitColor
        let project = Project(cwd: chat.cwd, chats: [])

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { model.leaveDetail() } label: {
                    Icon(.chevronLeft, size: 12, lineWidth: 1.7)
                        .foregroundStyle(pal.text)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(SurfaceButtonStyle(background: pal.seg, hover: pal.text.opacity(0.06), cornerRadius: 9))
                .help(s.back)
                .accessibilityLabel(s.back)

                VStack(alignment: .leading, spacing: 1) {
                    Text(chat.title)
                        .font(.ui(13.5, .semibold))
                        .foregroundStyle(pal.text)
                        .lineLimit(1)
                    Text(project.name + " · " + project.displayPath)
                        .font(.mono(10.5))
                        .foregroundStyle(pal.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(model.waitingFor(chat))
                    .font(.ui(10.5, .semibold))
                    .foregroundStyle(pal.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(wait.opacity(pal.isDark ? 0.28 : 0.22), in: Capsule())
                    .fixedSize()
            }
            .padding(.horizontal, 2)

            if let context = chat.request?.context, !context.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.lastMsg.uppercased())
                        .font(.ui(10.5, .semibold))
                        .tracking(0.42)
                        .foregroundStyle(pal.muted)
                    Text(context)
                        .font(.ui(12.5))
                        .lineSpacing(3.5)
                        .foregroundStyle(pal.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .island(pal)
            }

            RequestCard(model: model, request: chat.request)

            HStack(spacing: 8) {
                Text(s.replyInTerminal)
                    .font(.ui(11))
                    .foregroundStyle(pal.muted)
                Spacer(minLength: 0)
                Button { model.openInTerminal(chat.id) } label: {
                    HStack(spacing: 6) {
                        Text(s.openTerminal)
                        Icon(.arrowUpRight, size: 11)
                    }
                    .font(.ui(12, .medium))
                    .foregroundStyle(pal.text)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                }
                .buttonStyle(SurfaceButtonStyle(background: pal.island, hover: pal.text.opacity(0.05),
                                                cornerRadius: 9, border: pal.line))
                .keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 2, leading: 2, bottom: 0, trailing: 2))
        }
    }
}

private struct RequestCard: View {
    let model: AppModel
    let request: PendingRequest?

    var body: some View {
        let pal = model.palette
        let s = model.strings
        let wait = model.waitColor
        let label: String = switch request?.kind {
        case .permission:
            if let tool = request?.toolName, tool != "Bash" { s.askTool + tool } else { s.askPerm }
        case .question: s.askQ
        case nil: s.askGeneric
        }
        let options: [String] = {
            guard let request else { return [] }
            if !request.options.isEmpty { return request.options }
            guard request.kind == .permission, request.command != nil else { return [] }
            return request.allowAlways ? [s.optYes, s.optAlways, s.optNo] : [s.optYes, s.optNo]
        }()

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(wait).frame(width: 7, height: 7)
                Text(label).font(.ui(12, .semibold)).foregroundStyle(pal.text)
            }
            .padding(.horizontal, 2)

            if let command = request?.command, !command.isEmpty {
                Text("$ " + command)
                    .font(.mono(12))
                    .foregroundStyle(pal.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(pal.code, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)
            }

            if let question = request?.question, !question.isEmpty {
                Text(question)
                    .font(.ui(13))
                    .lineSpacing(3)
                    .foregroundStyle(pal.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }

            if !options.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                        let primary = i == 0
                        HStack(spacing: 10) {
                            Text(option).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(i + 1)").font(.mono(10.5)).opacity(0.7)
                        }
                        .font(.ui(12.5, primary ? .semibold : .medium))
                        .foregroundStyle(primary ? Color(hex: "#0b0b0c") : pal.text)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(primary ? wait : pal.seg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                // v1: ответ из панели не поддерживается.
                .opacity(0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 10))
        .island(pal, border: wait.opacity(0.45))
    }
}
