import SwiftUI
import AppKit

struct IslandTickerView: View {
    let steps: [IslandStep]
    let openDiff: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(steps.prefix(3)) { step in
                HStack {
                    Button(action: openDiff) {
                        HStack { Text(step.label).lineLimit(1); Spacer(); Text(step.ageLabel(now: Date())).foregroundColor(.white.opacity(0.4)); if !step.delta.isEmpty { Text(step.delta).foregroundColor(Color(hex: 0xE0824F)) } }
                    }.buttonStyle(.plain)
                    Button("copiar", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(step.label)\(step.delta.isEmpty ? "" : " · \(step.delta)")", forType: .string) }.buttonStyle(.plain).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                }.font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            }
            if !steps.isEmpty {
                Button("copiar actividad reciente", systemImage: "doc.on.clipboard") {
                    let lines = steps.prefix(3).map { "- \($0.label)\($0.delta.isEmpty ? "" : " · \($0.delta)") · \($0.ageLabel(now: Date()))" }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                }.buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            }
        }
    }
}
