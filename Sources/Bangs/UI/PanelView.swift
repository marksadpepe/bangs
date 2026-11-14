import SwiftUI

/// Окно панели: панель «вырастает» из чёлки.
struct PanelRoot: View {
    let model: AppModel

    var body: some View {
        let g = model.geometry
        let active = model.indicator.isActive
        let closed = CGSize(width: g.closedBodyWidth(active: active) + 2 * g.closedEar(active: active),
                            height: g.notchHeight)
        VStack(spacing: 0) {
            if model.isOpen {
                PanelView(model: model)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.panelFrame = $0 }
                    .transition(.notchExpand(from: closed))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Панель: чёрная полоса-шапка (продолжение чёлки) + тело с текущим экраном.
struct PanelView: View {
    let model: AppModel
    var scrollable = true

    var body: some View {
        let pal = model.palette
        VStack(spacing: 0) {
            PanelHeader(model: model)
                .frame(height: model.geometry.headerHeight)
            PanelBody(model: model, scrollable: scrollable)
                .background(pal.panel, in: UnevenRoundedRectangle(
                    topLeadingRadius: pal.bodyTopRadius, topTrailingRadius: pal.bodyTopRadius, style: .circular))
        }
        .frame(width: NotchGeometry.panelBodyWidth)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: NotchGeometry.openRadius,
                                          bottomTrailingRadius: NotchGeometry.openRadius, style: .circular))
        .padding(.horizontal, NotchGeometry.ear)
        .background {
            NotchSilhouette(ear: NotchGeometry.ear, bottomRadius: NotchGeometry.openRadius)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.45), radius: 25, y: 20)
        }
        .environment(\.colorScheme, pal.isDark ? .dark : .light)
    }
}

// MARK: - Шапка

private struct PanelHeader: View {
    let model: AppModel

    var body: some View {
        let g = model.geometry
        let side = max(80, (NotchGeometry.panelBodyWidth - g.notchWidth) / 2 - 20)
        HStack(spacing: 0) {
            AccountLabel(model: model)
                .frame(maxWidth: side, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                let done = model.doneCount, waiting = model.waitingCount
                Text(done > 0 ? "\(done)\(model.strings.completed)"
                     : waiting > 0 ? "\(waiting)\(model.strings.nWait)" : model.strings.allSeen)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(done > 0 ? model.doneColor : waiting > 0 ? model.waitColor : Palette.headerMuted)
                    .lineLimit(1)
                Button { model.onRequestClose?() } label: {
                    Icon(.chevronUp, size: 11)
                        .foregroundStyle(Palette.headerText)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(SurfaceButtonStyle(background: Palette.headerButton,
                                                hover: .white.opacity(0.06), cornerRadius: 12))
                .help(model.strings.collapse)
                .accessibilityLabel(model.strings.collapse)
            }
            .frame(maxWidth: side, alignment: .trailing)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }
}

private struct AccountLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            Icon(.asterisk, size: 12).foregroundStyle(model.doneColor)
            Text("Claude Code").foregroundStyle(Palette.headerText).fixedSize()
            if let account = model.account {
                Text("·").foregroundStyle(Palette.headerDim)
                Text(account.name).foregroundStyle(Palette.headerMuted).lineLimit(1)
            }
        }
        .font(.ui(12, .medium))
        .help(model.account?.tooltip ?? "")
    }
}

// MARK: - Тело

private struct PanelBody: View {
    let model: AppModel
    let scrollable: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                switch model.screen {
                case .list:
                    ChatListView(model: model, scrollable: scrollable).transition(.panelEnter)
                case .detail(let id):
                    if let chat = model.chat(id) {
                        ChatDetailView(model: model, chat: chat).transition(.panelEnter)
                    } else {
                        ChatListView(model: model, scrollable: scrollable).transition(.panelEnter)
                    }
                case .settings:
                    SettingsView(model: model).transition(.panelEnter)
                }
            }
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26), value: model.screen)

            if !isDetail {
                PanelFooter(model: model).padding(.top, 8)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    private var isDetail: Bool {
        if case .detail(let id) = model.screen, model.chat(id) != nil { return true }
        return false
    }
}

private struct PanelFooter: View {
    let model: AppModel

    var body: some View {
        let pal = model.palette
        let s = model.strings
        let settingsOpen = model.screen == .settings
        HStack(spacing: 0) {
            Button(settingsOpen ? "← " + s.backToChats : s.markAll) {
                if settingsOpen { model.screen = .list } else { model.markAllSeen() }
            }
            .buttonStyle(.plain)
            .font(.ui(11.5))
            .foregroundStyle(pal.muted)
            .padding(.vertical, 5)
            .padding(.horizontal, 4)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button { model.settings.lang = model.settings.lang == .ru ? .en : .ru } label: {
                    Text(model.settings.lang.rawValue.uppercased())
                        .font(.ui(11, .semibold))
                        .padding(.horizontal, 7)
                        .frame(minWidth: 32, minHeight: 26)
                }
                .help(s.language)

                Button { model.settings.theme = pal.isDark ? .light : .dark } label: {
                    Icon(pal.isDark ? .moon : .sun, size: 14, lineWidth: 1.5).frame(width: 28, height: 26)
                }
                .help(s.theme)

                Button { model.toggleSettings() } label: {
                    Icon(.sliders, size: 14, lineWidth: 1.5)
                        .frame(width: 28, height: 26)
                        .background(settingsOpen ? pal.seg : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .help(s.settings)
            }
            .buttonStyle(SurfaceButtonStyle(hover: pal.text.opacity(0.06), cornerRadius: 8))
            .foregroundStyle(pal.muted)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Переходы

extension AnyTransition {
    /// Появление экрана (CSS .enter: 0.26 с, сдвиг −6, масштаб 0.98).
    static var panelEnter: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: EnterModifier(progress: 0), identity: EnterModifier(progress: 1)),
            removal: AnyTransition.opacity.animation(.linear(duration: 0.01)))
    }

    /// Панель вырастает из чёлки: сначала чёрный силуэт, потом проявляется содержимое.
    static func notchExpand(from closed: CGSize) -> AnyTransition {
        .modifier(active: ExpandModifier(progress: 0, from: closed),
                  identity: ExpandModifier(progress: 1, from: closed))
    }
}

private struct EnterModifier: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.98 + 0.02 * progress, anchor: .top)
            .offset(y: -6 * (1 - progress))
    }
}

private struct ExpandModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGSize
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = progress
        let from = from
        // Содержимое скрыто под чёрным силуэтом, пока панель не раскрылась примерно на треть.
        let cover = min(1, max(0, 1 - (p - 0.3) / 0.6))
        content
            .overlay {
                NotchSilhouette(ear: NotchGeometry.ear, bottomRadius: NotchGeometry.openRadius)
                    .fill(Color.black)
                    .opacity(cover)
            }
            .visualEffect { view, proxy in
                let size = proxy.size
                let sx = size.width > 0 ? from.width / size.width : 1
                let sy = size.height > 0 ? from.height / size.height : 1
                return view.scaleEffect(x: sx + (1 - sx) * p, y: sy + (1 - sy) * p, anchor: .top)
            }
    }
}
