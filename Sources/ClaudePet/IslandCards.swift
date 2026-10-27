import SwiftUI
import AppKit

struct IslandActionButton: View {
    let title: String
    let fill: Color
    let ink: Color
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(ink)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(IslandPressStyle())
        .onHover { hovering = $0 }
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.easeOut(duration: 0.07), value: hovering)
    }
}

private struct IslandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct PermissionCardView: View {
    @ObservedObject var store: PetStore
    let ask: PermissionAsk
    @State private var showMore = false

    /// Permitir recordando la decision. Sin objetivo claro (comando compuesto) o con riesgo alto no hay alcance.
    @ViewBuilder private func scopeMenu(for ask: PermissionAsk, risk: PermissionRisk) -> some View {
        let canRemember = risk != .high && ApprovalRules.key(tool: ask.tool, detail: ask.detail) != nil
        if canRemember {
            Menu("permitir y recordar") {
                ForEach(ApprovalScope.allCases.filter { $0 != .once && $0.isAllowed(for: risk) }, id: \.self) { scope in
                    Button(scope == .project ? "este proyecto, 30 min" : scope == .session ? "esta sesión" : "siempre") { store.approveWithScope(ask.id, scope) }
                }
            }
            .menuStyle(.borderlessButton).font(.system(size: 11, design: .monospaced)).fixedSize()
            .accessibilityHint("permite esta petición y las iguales durante el tiempo elegido")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(ask.tool == "ExitPlanMode" ? "claude propone un plan" : "claude pide permiso").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0xEC9A6E))
                if store.permissionAsks.count > 1 { Text("+\(store.permissionAsks.count - 1) en espera").font(.system(size: 11, design: .monospaced)).foregroundColor(Color.white.opacity(0.5)) }
            }
            Text(ask.project.isEmpty ? ask.tool : "\(ask.tool) · \(ask.project)").font(.system(size: 12)).foregroundColor(Color.white.opacity(0.6)).lineLimit(1)
            let reading = PermissionRiskClassifier.classify(tool: ask.tool, detail: ask.detail, project: ask.project)
            Label("riesgo \(reading.risk.rawValue)", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(reading.risk.color)
            Text(reading.reason).font(.system(size: 10)).foregroundColor(Color.white.opacity(0.65)).lineLimit(2)
            if let secret = SecretDetector.find(in: ask.detail, path: ask.project) {
                Label("posible secreto: \(secret.label) · \(secret.prefix)", systemImage: "exclamationmark.shield.fill")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0xD85C5C))
            }
            if !ask.detail.isEmpty {
                let preview = PermissionPreviewBuilder.make(tool: ask.tool, detail: ask.detail, project: ask.project)
                Text(preview.lines.prefix(showMore ? preview.lines.count : min(8, preview.lines.count)).joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.white).lineLimit(showMore ? nil : 8).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                if preview.truncated { Button(showMore ? "ver menos" : "ver más") { showMore.toggle() }.buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(Color.white.opacity(0.7)) }
                Button("copiar detalle", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ask.detail, forType: .string) }.font(.system(size: 10, design: .monospaced)).buttonStyle(.plain).foregroundColor(Color.white.opacity(0.6))
            }
            Button("copiar permiso completo", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ask.clipboardText, forType: .string) }.font(.system(size: 10, design: .monospaced)).buttonStyle(.plain).foregroundColor(Color.white.opacity(0.6))
            HStack(spacing: 8) {
                IslandActionButton(title: ask.tool == "ExitPlanMode" ? "rechazar" : "denegar", fill: Color.white.opacity(0.1), ink: .white) { store.answerPermission(ask.id, .deny) }
                Spacer(minLength: 0)
                if ask.canAlways && ask.tool != "ExitPlanMode" { IslandActionButton(title: "siempre", fill: Color.white.opacity(0.1), ink: .white) { store.answerPermission(ask.id, .always) } }
                IslandActionButton(title: ask.tool == "ExitPlanMode" ? "aprobar plan" : "permitir", fill: Color(hex: 0xE0824F), ink: .black) { store.answerPermission(ask.id, .allow) }
                scopeMenu(for: ask, risk: reading.risk)
                IslandActionButton(title: "responder en terminal", fill: Color.white.opacity(0.06), ink: Color.white.opacity(0.7)) { store.dismissPermission(ask.id) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuestionCardView: View {
    @ObservedObject var store: PetStore
    let ask: QuestionAsk
    @Binding var selections: [Int: Set<Int>]
    @Binding var index: Int
    @Binding var freeText: String
    let commit: (QuestionAsk, Int, [Int]) -> Void

    private func option(_ title: String, description: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(selected ? .black : .white)
                if !description.isEmpty { Text(description).font(.system(size: 9)).foregroundColor(selected ? Color.black.opacity(0.7) : Color.white.opacity(0.55)).lineLimit(1) }
            }.padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(selected ? Color(hex: 0x5270E8) : Color.white.opacity(0.1)))
        }.buttonStyle(.plain)
    }

    var body: some View {
        let current = min(index, max(0, ask.questions.count - 1))
        let q = ask.questions[current]
        let multi = q.multiSelect
        let selected = selections[current, default: []]
        let hasOther = selected.contains { q.options.indices.contains($0) && q.options[$0].label.lowercased().contains("otra") }
        return VStack(alignment: .leading, spacing: 8) {
            Text("claude pregunta").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(Color(hex: 0xEC9A6E))
            if ask.questions.count > 1 { Text("pregunta \(current + 1) de \(ask.questions.count)").font(.system(size: 10, design: .monospaced)).foregroundColor(Color.white.opacity(0.5)) }
            Text(q.question).font(.system(size: 13)).foregroundColor(.white).lineLimit(2)
            Button("copiar pregunta", systemImage: "doc.on.clipboard") { let options = q.options.map(\.label).joined(separator: ", "); NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(q.question)\nopciones: \(options)", forType: .string) }.font(.system(size: 10, design: .monospaced)).buttonStyle(.plain).foregroundColor(Color.white.opacity(0.6))
            HStack(spacing: 6) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { optionIndex, item in
                    let isSelected = selected.contains(optionIndex)
                    option(item.label, description: item.description, selected: isSelected) {
                        let isOther = item.label.lowercased().contains("otra")
                        if multi || isOther {
                            if isSelected { selections[current, default: []].remove(optionIndex) } else { selections[current, default: []].insert(optionIndex) }
                        } else { commit(ask, current, [optionIndex]) }
                    }
                }
            }
            if hasOther { TextField("escribe tu respuesta", text: $freeText).textFieldStyle(.roundedBorder).font(.system(size: 12)) }
            if multi || hasOther {
                IslandActionButton(title: current + 1 < ask.questions.count ? "siguiente" : "confirmar selección", fill: Color(hex: 0xE0824F), ink: .black) { commit(ask, current, Array(selected).sorted()) }
                    .disabled(selected.isEmpty || (hasOther && freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            IslandActionButton(title: "responder en terminal", fill: Color.white.opacity(0.06), ink: Color.white.opacity(0.7)) { store.dismissQuestion(ask.id); selections.removeAll(); index = 0; freeText = "" }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
