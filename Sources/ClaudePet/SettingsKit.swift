import SwiftUI
import AppKit

/// Tokens compartidos para los ajustes: telemetría oscura, datos monoespaciados y una sola señal ámbar.
enum SettingsTheme {
    static let claude = DashboardTheme.amber
    static let codex = DashboardTheme.ember
    static let codexLight = DashboardTheme.ember
    static let violet = Color(hex: 0xFF944D)
    /// Un solo color para controles que no admiten degradado.
    static let blue = DashboardTheme.amber
    static let green = Color(hex: 0x33CC5C)
    static let red = Color(hex: 0xE6213F)
    static let amber = Color(hex: 0xF2B632)
    static let mute = DashboardTheme.muted
    static let line = DashboardTheme.line
    static let duo = DashboardTheme.accent
    static let duoDiagonal = LinearGradient(colors: [claude, violet, codexLight], startPoint: .topLeading, endPoint: .bottomTrailing)
    static var cardBorder: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.05), Color.white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var background: some View { SettingsBackground() }
}

/// Vidrio real: el desenfoque lo pone macOS detras de la ventana; encima, dos luces tenues, una por agente.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = .behindWindow; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct SettingsBackground: View {
    var body: some View {
        ZStack {
            VisualEffect()
            DashboardTheme.black.opacity(0.88)
            RadialGradient(colors: [SettingsTheme.claude.opacity(0.16), .clear], center: .topLeading, startRadius: 10, endRadius: 520)
            LinearGradient(colors: [.clear, DashboardTheme.ember.opacity(0.05)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

struct SCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 8) {
                    Capsule().fill(SettingsTheme.duo).frame(width: 14, height: 3)
                    Text(title.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(SettingsTheme.mute)
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(SettingsTheme.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DashboardTheme.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SettingsTheme.cardBorder, lineWidth: 1))
    }
}

struct SDivider: View {
    var body: some View { Rectangle().fill(SettingsTheme.line).frame(height: 1).padding(.horizontal, 20) }
}

struct SRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(SettingsTheme.mute).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

/// Interruptor de vidrio: el dúo de color cuando esta encendido.
struct GlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? AnyShapeStyle(SettingsTheme.duo) : AnyShapeStyle(Color.white.opacity(0.14)))
                Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                Circle().fill(Color.white).padding(3).shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .frame(width: 42, height: 24)
            .animation(.easeOut(duration: 0.16), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

struct SToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var body: some View {
        SRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(GlassToggleStyle())
        }
    }
}

struct SMenu<T: Hashable>: View {
    let title: String
    var detail: String?
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        SRow(title: title, detail: detail) {
            Menu {
                ForEach(options, id: \.0) { option in Button(option.1) { selection = option.0 } }
            } label: {
                HStack(spacing: 8) {
                    Text(options.first { $0.0 == selection }?.1 ?? "").font(.system(size: 12.5, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(SettingsTheme.mute)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .overlay(Capsule().stroke(SettingsTheme.line, lineWidth: 1))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(title)
        }
    }
}

struct SSegmented<T: Hashable>: View {
    let title: String
    var detail: String?
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        SRow(title: title, detail: detail) {
            HStack(spacing: 2) {
                ForEach(options, id: \.0) { option in
                    let on = option.0 == selection
                    Button { withAnimation(.easeOut(duration: 0.16)) { selection = option.0 } } label: {
                        Text(option.1).font(.system(size: 12, weight: on ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(on ? Color.white : Color.white.opacity(0.7))
                            .background(Capsule().fill(on ? AnyShapeStyle(SettingsTheme.duo.opacity(0.85)) : AnyShapeStyle(Color.clear)))
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3).background(Capsule().fill(Color.white.opacity(0.08))).overlay(Capsule().stroke(SettingsTheme.line, lineWidth: 1))
        }
    }
}

/// Barra de vidrio que se arrastra; sirve de deslizador en ajustes.
struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    var width: CGFloat = 190
    var body: some View {
        GeometryReader { geo in
            let f = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 5)
                Capsule().fill(SettingsTheme.duo).frame(width: max(5, geo.size.width * f), height: 5)
                Circle().fill(Color.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: max(0, min(geo.size.width - 16, geo.size.width * f - 8)))
            }
            .frame(maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let raw = range.lowerBound + Double(max(0, min(1, g.location.x / max(1, geo.size.width)))) * (range.upperBound - range.lowerBound)
                let snapped = (raw / step).rounded() * step
                let next = max(range.lowerBound, min(range.upperBound, snapped))
                if next != value { value = next }
            })
        }
        .frame(width: width, height: 22)
        .accessibilityElement().accessibilityValue("\(Int(((value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100).rounded())) %")
        .accessibilityAdjustableAction { dir in
            let delta = dir == .increment ? step : -step
            value = max(range.lowerBound, min(range.upperBound, value + delta))
        }
    }
}

struct SSlider: View {
    let title: String
    var detail: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    let format: (Double) -> String
    var body: some View {
        SRow(title: title, detail: detail) {
            HStack(spacing: 12) {
                GlassSlider(value: $value, range: range, step: step)
                Text(format(value)).font(.system(size: 12, design: .monospaced)).foregroundStyle(SettingsTheme.mute).frame(width: 58, alignment: .trailing)
            }
        }
    }
}

struct SButton: View {
    let title: String
    var symbol: String?
    var prominent = false
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(destructive ? SettingsTheme.red : .white)
            .background(Capsule().fill(prominent ? AnyShapeStyle(SettingsTheme.duo) : AnyShapeStyle(Color.white.opacity(0.1))))
            .overlay(Capsule().stroke(prominent ? Color.white.opacity(0.25) : SettingsTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct SBadge: View {
    let text: String
    var color: Color = SettingsTheme.blue
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color).background(Capsule().fill(color.opacity(0.16)))
    }
}

struct SStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 28, weight: .bold)).monospacedDigit().foregroundStyle(SettingsTheme.duo)
            Text(label).font(.system(size: 11)).foregroundStyle(SettingsTheme.mute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(SettingsTheme.cardBorder, lineWidth: 1))
    }
}

/// Casilla seleccionable con una mascota dentro: skins y atuendos.
struct SpriteTile<Content: View>: View {
    let title: String
    var detail: String?
    var selected: Bool
    var locked = false
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                content.frame(height: 64).opacity(locked ? 0.35 : 1)
                VStack(spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    if let detail { Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(SettingsTheme.mute) }
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Color.white.opacity(0.11) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? AnyShapeStyle(SettingsTheme.duoDiagonal) : AnyShapeStyle(SettingsTheme.line), lineWidth: selected ? 1.6 : 1))
            .overlay(alignment: .topTrailing) {
                if locked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(SettingsTheme.mute).padding(8) }
                else if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(SettingsTheme.duo).padding(7) }
            }
        }
        .buttonStyle(.plain).disabled(locked)
        .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Relanza la app tras importar o restablecer: los ajustes se leen al arrancar.
enum AppRelauncher {
    static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    static func relaunch() {
        guard canRelaunch else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1.2; /usr/bin/open -n \"$0\"", Bundle.main.bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
