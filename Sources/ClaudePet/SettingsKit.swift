import SwiftUI
import AppKit

/// Tokens compartidos para los ajustes: cristal oscuro, datos monoespaciados y un solo acento (el naranja de claude).
/// Cada agente conserva su color propio solo donde se habla de el: claude naranja, codex azul.
enum SettingsTheme {
    static let agentClaude = Color(hex: 0xE0824F)
    static let agentCodex = Color(hex: 0x5270E8)
    /// Tinta oscura para texto sobre el acento: contraste alto sobre el naranja.
    static let onAccent = Color(hex: 0x15110D)
    static let accent = agentClaude
    static let claude = agentClaude
    static let codex = agentCodex
    static let codexLight = agentCodex
    static let violet = accent
    /// Un solo color para controles que no admiten degradado.
    static let blue = accent
    static let green = Color(hex: 0x33CC5C)
    static let red = Color(hex: 0xE6213F)
    static let amber = Color(hex: 0xF2B632)
    static let mute = DashboardTheme.muted
    static let line = DashboardTheme.line
    /// Antes un degradado; ahora un unico tono para que nada parezca de plantilla. Se conserva el nombre para las paginas.
    static let duo = LinearGradient(colors: [accent, accent], startPoint: .leading, endPoint: .trailing)
    static let duoDiagonal = duo
    static var cardBorder: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var background: some View { SettingsBackground() }

    /// Con contraste alto las lineas y el texto secundario suben para llegar a 4,5:1 sobre el cristal.
    static func hairline(_ high: Bool) -> Color { high ? Color.white.opacity(0.45) : Color.white.opacity(0.10) }
    static func muted(_ high: Bool) -> Color { high ? Color.white.opacity(0.88) : DashboardTheme.muted }
    static func agentColor(_ agent: String) -> Color { agent == "codex" ? agentCodex : agentClaude }
}

/// Densidad de las filas de ajustes. Se guarda como preferencia de vista.
enum SettingsDensity: String, CaseIterable, Identifiable {
    case comfortable = "comoda", compact = "compacta"
    var id: String { rawValue }
    static let storageKey = "settingsDensity"
    var title: String { self == .comfortable ? "cómoda" : "compacta" }
    var rowV: CGFloat { self == .comfortable ? 14 : 7 }
    var rowH: CGFloat { self == .comfortable ? 22 : 16 }
    var pageSpacing: CGFloat { self == .comfortable ? 22 : 12 }
    var cardGap: CGFloat { self == .comfortable ? 14 : 8 }
    var radius: CGFloat { self == .comfortable ? 14 : 10 }
    static func decode(_ raw: String?) -> SettingsDensity { raw.flatMap(SettingsDensity.init(rawValue:)) ?? .comfortable }
}

private struct SettingsDensityKey: EnvironmentKey { static let defaultValue = SettingsDensity.comfortable }
private struct SettingsContrastKey: EnvironmentKey { static let defaultValue = false }
private struct SettingsReduceMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var settingsDensity: SettingsDensity { get { self[SettingsDensityKey.self] } set { self[SettingsDensityKey.self] = newValue } }
    var settingsHighContrast: Bool { get { self[SettingsContrastKey.self] } set { self[SettingsContrastKey.self] = newValue } }
    var settingsReduceMotion: Bool { get { self[SettingsReduceMotionKey.self] } set { self[SettingsReduceMotionKey.self] = newValue } }
}

/// Etiqueta mono pequena en mayusculas: el rotulo de toda seccion, tarjeta y cifra.
struct SLabel: View {
    let text: String
    var tint: Color?
    @Environment(\.settingsHighContrast) private var high
    init(_ text: String, tint: Color? = nil) { self.text = text; self.tint = tint }
    var body: some View {
        Text(verbatim: L.tr(text).uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.4)
            .foregroundStyle(tint ?? SettingsTheme.muted(high))
    }
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

/// Tarjeta de ajustes: rotulo mono arriba, filas separadas por una linea fina y un solo borde de cristal.
struct SCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content
    @Environment(\.settingsDensity) private var density
    @Environment(\.settingsHighContrast) private var high

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 8) {
                    Rectangle().fill(SettingsTheme.accent).frame(width: 6, height: 6)
                    SLabel(title)
                }
                .padding(.horizontal, density.rowH).padding(.top, density == .comfortable ? 18 : 12).padding(.bottom, 2)
            }
            VStack(alignment: .leading, spacing: 0) { content }
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(SettingsTheme.muted(high))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, density.rowH).padding(.top, 2).padding(.bottom, density == .comfortable ? 16 : 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: density.radius, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: density.radius, style: .continuous).strokeBorder(high ? SettingsTheme.hairline(true) : Color.white.opacity(0.09), lineWidth: 1))
    }
}

struct SDivider: View {
    @Environment(\.settingsDensity) private var density
    @Environment(\.settingsHighContrast) private var high
    var body: some View { Rectangle().fill(SettingsTheme.hairline(high).opacity(high ? 1 : 0.7)).frame(height: 1).padding(.horizontal, density.rowH) }
}

struct SRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing
    @Environment(\.settingsDensity) private var density
    @Environment(\.settingsHighContrast) private var high

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(SettingsTheme.muted(high)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, density.rowH).padding(.vertical, density.rowV)
    }
}

/// Interruptor de cristal: un solo tono de acento cuando esta encendido; la perilla marca el estado tambien sin color.
struct GlassToggleStyle: ToggleStyle {
    @Environment(\.settingsReduceMotion) private var reduceMotion
    @Environment(\.settingsHighContrast) private var high
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? SettingsTheme.accent : Color.white.opacity(0.13))
                Capsule().strokeBorder(high ? Color.white.opacity(0.7) : Color.white.opacity(configuration.isOn ? 0.0 : 0.16), lineWidth: 1)
                Circle().fill(configuration.isOn ? SettingsTheme.onAccent : Color.white.opacity(0.85)).padding(3.5)
            }
            .frame(width: 40, height: 22)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isOn)
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
    @Environment(\.settingsHighContrast) private var high
    var body: some View {
        SRow(title: title, detail: detail) {
            Menu {
                ForEach(options, id: \.0) { option in Button(option.1) { selection = option.0 } }
            } label: {
                HStack(spacing: 8) {
                    Text(options.first { $0.0 == selection }?.1 ?? "").font(.system(size: 12, weight: .medium, design: .monospaced))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(SettingsTheme.muted(high))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(SettingsTheme.hairline(high), lineWidth: 1))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(title)
        }
    }
}

/// Selector de opciones en fila: la elegida se rellena con el acento y lleva el texto oscuro.
struct SSegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var compact = false
    @Environment(\.settingsReduceMotion) private var reduceMotion
    @Environment(\.settingsHighContrast) private var high
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option in
                let on = option.0 == selection
                Button {
                    if reduceMotion { selection = option.0 } else { withAnimation(.easeOut(duration: 0.14)) { selection = option.0 } }
                } label: {
                    Text(option.1).font(.system(size: compact ? 11 : 12, weight: on ? .semibold : .regular, design: .monospaced))
                        .padding(.horizontal, compact ? 9 : 12).padding(.vertical, compact ? 4 : 6)
                        .foregroundStyle(on ? SettingsTheme.onAccent : Color.white.opacity(0.78))
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? SettingsTheme.accent : Color.clear))
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2.5)
        .background(RoundedRectangle(cornerRadius: 8.5, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8.5, style: .continuous).stroke(SettingsTheme.hairline(high), lineWidth: 1))
    }
}

struct SSegmented<T: Hashable>: View {
    let title: String
    var detail: String?
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        SRow(title: title, detail: detail) { SSegmentedControl(selection: $selection, options: options) }
    }
}

/// Filtro en forma de ficha: etiqueta mono, contador opcional y un estado seleccionado que no depende solo del color.
struct SChip: View {
    let title: String
    var count: Int?
    var symbol: String?
    var selected: Bool
    var tint: Color = SettingsTheme.accent
    let action: () -> Void
    @Environment(\.settingsHighContrast) private var high
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .medium)) }
                Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular, design: .monospaced))
                if let count { Text("\(count)").font(.system(size: 10, design: .monospaced)).opacity(0.7) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(selected ? SettingsTheme.onAccent : Color.white.opacity(0.78))
            .background(Capsule().fill(selected ? tint : Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(selected ? Color.clear : SettingsTheme.hairline(high), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
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
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                Capsule().fill(SettingsTheme.accent).frame(width: max(4, geo.size.width * f), height: 4)
                Circle().fill(Color.white).frame(width: 14, height: 14).shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: max(0, min(geo.size.width - 14, geo.size.width * f - 7)))
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
    @Environment(\.settingsHighContrast) private var high
    var body: some View {
        SRow(title: title, detail: detail) {
            HStack(spacing: 12) {
                GlassSlider(value: $value, range: range, step: step)
                Text(format(value)).font(.system(size: 12, design: .monospaced)).foregroundStyle(SettingsTheme.muted(high)).frame(width: 58, alignment: .trailing)
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
    @Environment(\.settingsHighContrast) private var high
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10.5, weight: .medium)) }
                Text(title).font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 12).padding(.vertical, 6.5)
            .foregroundStyle(prominent ? SettingsTheme.onAccent : (destructive ? SettingsTheme.red : .white))
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(prominent ? AnyShapeStyle(SettingsTheme.accent) : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(prominent ? Color.clear : SettingsTheme.hairline(high), lineWidth: 1))
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

/// Cifra grande con su rotulo mono debajo. Sin caja: la jerarquia la da la escala.
struct SStat: View {
    let value: String
    let label: String
    var tint: Color = Color.white
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 34, weight: .semibold)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            SLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Tarjeta de tablero: rotulo, contenido libre y un dato opcional en la esquina. Para las paginas de inicio.
struct STile<Content: View>: View {
    let title: String
    var trailing: String?
    var tint: Color = SettingsTheme.accent
    @ViewBuilder var content: Content
    @Environment(\.settingsDensity) private var density
    @Environment(\.settingsHighContrast) private var high
    var body: some View {
        VStack(alignment: .leading, spacing: density == .comfortable ? 14 : 9) {
            HStack(spacing: 7) {
                Rectangle().fill(tint).frame(width: 6, height: 6)
                SLabel(title)
                Spacer(minLength: 6)
                if let trailing { Text(trailing).font(.system(size: 10, design: .monospaced)).foregroundStyle(SettingsTheme.muted(high)) }
            }
            content
        }
        .padding(density == .comfortable ? 18 : 13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: density.radius, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: density.radius, style: .continuous).strokeBorder(high ? SettingsTheme.hairline(true) : Color.white.opacity(0.09), lineWidth: 1))
    }
}

/// Medidor horizontal fino: `fraction` de 0 a 1. Se anima solo al cambiar el valor.
struct SMeter: View {
    var fraction: Double
    var tint: Color = SettingsTheme.accent
    var height: CGFloat = 5
    @Environment(\.settingsReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(tint).frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fraction)
        .accessibilityHidden(true)
    }
}

/// Grafica de barras dibujada con Canvas. Al aparecer o cambiar los datos las barras crecen desde la base (0,45 s);
/// con "reducir movimiento" aparecen ya completas. No hay temporizadores: en reposo no cuesta nada.
struct SBars: View {
    var values: [Double]
    var labels: [String] = []
    var highlight: Int?
    var tint: Color = SettingsTheme.accent
    var height: CGFloat = 70
    var summary = ""
    @State private var progress = 0.0
    @Environment(\.settingsReduceMotion) private var reduceMotion
    @Environment(\.settingsHighContrast) private var high

    var body: some View {
        VStack(spacing: 6) {
            BarsCanvas(values: values, highlight: highlight ?? values.count - 1, tint: tint, high: high, progress: progress).frame(height: height)
            if !labels.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                        Text(l).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(i == (highlight ?? values.count - 1) ? Color.white : SettingsTheme.muted(high))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear { grow() }
        .onChange(of: values) { _ in grow() }
        .accessibilityElement(children: .ignore).accessibilityLabel(summary)
    }

    private func grow() {
        if reduceMotion { progress = 1; return }
        progress = 0
        withAnimation(.easeOut(duration: 0.45)) { progress = 1 }
    }
}

private struct BarsCanvas: View, Animatable {
    var values: [Double]
    var highlight: Int
    var tint: Color
    var high: Bool
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    var body: some View {
        Canvas { gc, size in
            guard !values.isEmpty else { return }
            let top = max(values.max() ?? 1, 1)
            let slot = size.width / CGFloat(values.count)
            let barW = min(26, max(4, slot * 0.58))
            gc.fill(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(SettingsTheme.hairline(high)))
            for (i, v) in values.enumerated() {
                let h = v <= 0 ? 2 : max(3, (size.height - 4) * CGFloat(v / top) * CGFloat(progress))
                let rect = CGRect(x: slot * CGFloat(i) + (slot - barW) / 2, y: size.height - 1 - h, width: barW, height: h)
                let on = i == highlight
                gc.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(v <= 0 ? Color.white.opacity(0.14) : (on ? tint : tint.opacity(high ? 0.65 : 0.38))))
            }
        }
    }
}

/// Anillo de porcentaje con la cifra dentro. `fraction` de 0 a 1.
struct SRing: View {
    var fraction: Double
    var label: String
    var tint: Color = SettingsTheme.accent
    var size: CGFloat = 76
    @Environment(\.settingsReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, fraction)))).stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .butt)).rotationEffect(.degrees(-90))
            Text(label).font(.system(size: size * 0.24, weight: .semibold, design: .monospaced)).monospacedDigit()
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: fraction)
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
