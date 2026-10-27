import SwiftUI
import AppKit

/// Estilo de la ventana de ajustes: carbon oscuro, tarjetas de cristal y un unico azul de accion.
enum SettingsTheme {
    static let blue = Color(hex: 0x2966ED)
    static let green = Color(hex: 0x33CC5C)
    static let red = Color(hex: 0xE6213F)
    static let amber = Color(hex: 0xF2B632)
    static let mute = Color.white.opacity(0.55)
    static let line = Color.white.opacity(0.11)
    static var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x121318), Color(hex: 0x1B1C23)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [blue.opacity(0.16), .clear], center: .topLeading, startRadius: 20, endRadius: 560)
        }
    }
}

struct SCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(SettingsTheme.mute)
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
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(SettingsTheme.line, lineWidth: 1))
    }
}

struct SDivider: View {
    var body: some View { Rectangle().fill(SettingsTheme.line).frame(height: 1).padding(.leading, 20) }
}

struct SRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium))
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

struct SToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var body: some View {
        SRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(SettingsTheme.blue)
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
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
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
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 300)
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
                Slider(value: $value, in: range, step: step).tint(SettingsTheme.blue).frame(width: 190)
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
            .background(Capsule().fill(prominent ? SettingsTheme.blue : Color.white.opacity(0.1)))
            .overlay(Capsule().stroke(prominent ? .clear : SettingsTheme.line, lineWidth: 1))
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
            Text(value).font(.system(size: 28, weight: .bold)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(SettingsTheme.mute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(SettingsTheme.line, lineWidth: 1))
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
