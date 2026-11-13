import SwiftUI

extension ChangeDiff {
    /// Alto de la lista desplegada: lo que ocupan sus filas (unos 15 pt cada una) con tope, para que una lista corta no deje un hueco.
    var listHeight: CGFloat {
        let more = hidden + trimmed > 0 ? 18 : 0
        return min(PermissionChangeBox.listHeight, CGFloat(lines.count) * 15 + CGFloat(more))
    }
}

/// Colores del diff: sobrios, para que el codigo siga siendo lo que se lee.
enum ChangePalette {
    static let addedInk = Color(hex: 0x9BD3AE)
    static let addedFill = Color(hex: 0x6CCB8A).opacity(0.11)
    static let removedInk = Color(hex: 0xE3A0A0)
    static let removedFill = Color(hex: 0xD85C5C).opacity(0.12)
    static let claude = Color(hex: 0xE0824F)
}

/// El cambio dentro de la tarjeta del permiso: una fila con la ruta y `+12 −3` siempre visible y, desplegado, las lineas con scroll.
struct PermissionChangeBox: View {
    let path: String
    let change: ChangeDiff
    let open: Bool
    let toggle: () -> Void
    /// Alto maximo de la zona con scroll.
    static let listHeight: CGFloat = 132

    private var fileName: String { path.isEmpty ? "—" : (path as NSString).lastPathComponent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Text(verbatim: fileName).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.white)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if !change.tag.isEmpty {
                        Text(verbatim: L.tr(change.tag)).font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                    }
                    if change.partial {
                        Text("parcial").font(.system(size: 9.5, design: .monospaced)).foregroundColor(Color(hex: 0xE7B45B)).lineLimit(1)
                    }
                    if change.shape != .cellDelete {
                        HStack(spacing: 5) {
                            Text(verbatim: "+\(change.added)").foregroundColor(ChangePalette.addedInk)
                            if change.counts.contains("−") { Text(verbatim: "−\(change.removed)").foregroundColor(ChangePalette.removedInk) }
                        }.font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    if !change.lines.isEmpty {
                        HStack(spacing: 3) {
                            Text(open ? "ocultar" : "ver cambio").font(.system(size: 9.5, design: .monospaced))
                            Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                        }.foregroundColor(ChangePalette.claude)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(change.lines.isEmpty)
            .help(path)
            .accessibilityLabel("cambio en \(fileName): \(change.counts) \(L.tr(change.tag))")
            .accessibilityHint(open ? "oculta las líneas del cambio" : "muestra las líneas del cambio")
            if open && !change.lines.isEmpty {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                lines
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("copiar ruta", systemImage: "doc.on.clipboard") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
        }
    }

    private var listHeight: CGFloat { change.listHeight }

    @ViewBuilder private var lines: some View {
        if IslandSnapshot.isRendering {
            // ImageRenderer no dibuja ScrollView: la captura muestra el principio de la lista, igual que la tarjeta recien abierta
            rows.frame(height: listHeight, alignment: .top).clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) { rows }
                .frame(height: listHeight)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10).allowsHitTesting(false)
                }
        }
    }

    private var rows: some View {
        let more = change.hidden + change.trimmed
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(change.lines.enumerated()), id: \.offset) { _, line in row(line) }
            if more > 0 {
                Text(verbatim: L.tr("y \(more) líneas más")).font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 8).padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func row(_ line: ChangeLine) -> some View {
        switch line.kind {
        case .gap:
            Text(verbatim: line.count > 0 ? "⋯  " + L.tr("\(line.count) líneas sin cambios") : "⋯")
                .font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 8).padding(.vertical, 2)
        case .context, .added, .removed:
            let added = line.kind == .added, removed = line.kind == .removed
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: added ? "+" : removed ? "−" : " ").foregroundColor((added ? ChangePalette.addedInk : ChangePalette.removedInk).opacity(0.7)).frame(width: 8)
                Text(verbatim: line.text.isEmpty ? " " : line.text).foregroundColor(added ? ChangePalette.addedInk : removed ? ChangePalette.removedInk : .white.opacity(0.6))
                    .lineLimit(1).truncationMode(.tail)
            }
            .font(.system(size: 10.5, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(added ? ChangePalette.addedFill : removed ? ChangePalette.removedFill : Color.clear)
        }
    }
}
