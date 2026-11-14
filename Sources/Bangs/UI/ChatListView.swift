import SwiftUI

/// Экран списка: островки-проекты с чатами.
struct ChatListView: View {
    let model: AppModel
    var scrollable = true

    var body: some View {
        if scrollable {
            ViewThatFits(in: .vertical) {
                list
                ScrollView(.vertical, showsIndicators: false) { list }
            }
            .frame(maxHeight: model.maxListHeight)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 7) {
            let projects = model.projects
            if projects.isEmpty {
                Text(model.strings.empty)
                    .font(.ui(12.5))
                    .foregroundStyle(model.palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .island(model.palette)
            } else {
                ForEach(projects) { ProjectIsland(model: model, project: $0) }
            }
        }
    }
}

private struct ProjectIsland: View {
    let model: AppModel
    let project: Project

    var body: some View {
        let pal = model.palette
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(project.name)
                    .font(.ui(12.5, .semibold))
                    .foregroundStyle(pal.text)
                    .lineLimit(1)
                    .layoutPriority(2)
                Text(project.displayPath)
                    .font(.mono(10.5))
                    .foregroundStyle(pal.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(model.summary(for: project))
                    .font(.ui(11))
                    .foregroundStyle(pal.muted)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            ForEach(project.chats) { ChatRow(model: model, chat: $0) }
        }
        .padding(EdgeInsets(top: 8, leading: 6, bottom: 4, trailing: 6))
        .island(pal)
    }
}

private struct ChatRow: View {
    let model: AppModel
    let chat: Chat

    var body: some View {
        let pal = model.palette
        let st = chat.status
        let done = model.doneColor, wait = model.waitColor
        let strong = pal.isDark ? 0.28 : 0.22

        Button { model.tap(chat) } label: {
            HStack(spacing: 9) {
                StatusDot(status: st, model: model)
                Text(chat.title)
                    .font(.ui(12.5))
                    .foregroundStyle(st == .seen ? pal.seenTitle : pal.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.meta(for: chat))
                    .font(.ui(11))
                    .foregroundStyle(pal.muted)
                    .lineLimit(1)
                    .fixedSize()
                if st == .done || st.isWaiting {
                    Text(st == .done ? model.strings.done : model.strings.wait)
                        .font(.ui(10.5, .semibold))
                        .foregroundStyle(st == .done || st == .waiting ? pal.text : pal.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(st == .done ? done.opacity(strong) : wait.opacity(st == .waiting ? strong : 0.12),
                                    in: Capsule())
                        .fixedSize()
                }
                if st.isWaiting {
                    Icon(.chevronRight, size: 10).foregroundStyle(pal.muted)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
        }
        .buttonStyle(SurfaceButtonStyle(
            background: st == .done ? done.opacity(pal.isDark ? 0.09 : 0.10)
                : st == .waiting ? wait.opacity(pal.isDark ? 0.08 : 0.09) : .clear,
            hover: pal.text.opacity(0.04),
            cornerRadius: 9))
    }
}

/// Точка статуса (7 pt): цвет/обводка/пульсация по статусу.
struct StatusDot: View {
    let status: ChatStatus
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticRendering) private var staticRendering
    @State private var pulse = false

    var body: some View {
        let pal = model.palette
        let done = model.doneColor, wait = model.waitColor
        ZStack {
            switch status {
            case .done:
                Circle().fill(done).shadow(color: done.opacity(0.7), radius: 3.5)
            case .waiting:
                Circle().fill(wait).shadow(color: wait.opacity(0.6), radius: 3.5)
            case .waitSeen, .denied:
                Circle().fill(wait.opacity(0.3)).overlay(Circle().strokeBorder(wait, lineWidth: 1.5))
            case .working:
                Circle().fill(pal.working).opacity(pulse ? 0.3 : 1)
            case .seen:
                Circle().strokeBorder(pal.seenRing, lineWidth: 1.5)
            }
        }
        .frame(width: 7, height: 7)
        .onAppear {
            guard status == .working, !reduceMotion, !staticRendering else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
