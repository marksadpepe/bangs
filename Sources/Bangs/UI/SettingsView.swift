import AppKit
import SwiftUI

/// Экран настроек: тема, язык, цвета «готово» и «ждёт».
struct SettingsView: View {
    let model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        let pal = model.palette
        let s = model.strings
        let st = model.settings

        VStack(spacing: 14) {
            row(s.theme) {
                Segmented(options: [(ThemeMode.dark, s.dark), (.light, s.light)],
                          selection: st.theme, pal: pal) { st.theme = $0 }
            }
            row(s.language) {
                Segmented(options: [(Lang.ru, "Русский"), (.en, "English")],
                          selection: st.lang, pal: pal) { st.lang = $0 }
            }
            row(s.doneColor) {
                Swatches(colors: AppSettings.donePalette, selected: st.doneColor, pal: pal) { st.doneColor = $0 }
            }
            row(s.waitColor) {
                Swatches(colors: AppSettings.waitPalette, selected: st.waitColor, pal: pal) { st.waitColor = $0 }
            }
            row(s.jumpOnClick) {
                PillSwitch(isOn: st.jumpOnClick, accent: model.doneColor, pal: pal) { st.jumpOnClick = $0 }
            }
            row(s.launchAtLogin) {
                PillSwitch(isOn: launchAtLogin, accent: model.doneColor, pal: pal) { launchAtLogin = LoginItem.set($0) }
            }
            HStack {
                Button(s.quit) { NSApp.terminate(nil) }
                Spacer()
                Button(s.reset) { st.resetColors() }
            }
            .buttonStyle(.plain)
            .font(.ui(11.5))
            .foregroundStyle(pal.muted)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .island(pal)
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(.ui(12.5, .semibold)).foregroundStyle(model.palette.text)
            Spacer()
            control()
        }
    }
}

private struct Segmented<Value: Equatable>: View {
    let options: [(Value, String)]
    let selection: Value
    let pal: Palette
    let pick: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.0 == selection
                Button { pick(option.0) } label: {
                    Text(option.1)
                        .font(.ui(11.5))
                        .foregroundStyle(on ? pal.text : pal.muted)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(on ? pal.segOn : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(pal.seg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct Swatches: View {
    let colors: [String]
    let selected: String
    let pal: Palette
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(colors, id: \.self) { hex in
                let on = hex.caseInsensitiveCompare(selected) == .orderedSame
                Button { pick(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .background {
                            if on { Circle().stroke(Color(hex: hex), lineWidth: 2).frame(width: 28, height: 28) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hex)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Переключатель в стиле панели (системный NSSwitch выбивается из дизайна).
private struct PillSwitch: View {
    let isOn: Bool
    let accent: Color
    let pal: Palette
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!isOn) } label: {
            Capsule()
                .fill(isOn ? accent : pal.segOn)
                .frame(width: 32, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 14, height: 14).padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                }
                .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
