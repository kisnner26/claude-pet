import SwiftUI

struct ChangedFile: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let added: Int
    let deleted: Int
    let untracked: Bool
    let staged: Bool
    let conflict: Bool
    let modified: Date?
    /// Peso real del archivo en el mapa: líneas tocadas (en archivos nuevos, sus líneas).
    var weight: Double { Double(max(1, added + deleted)) }
    var name: String { (path as NSString).lastPathComponent }
}

enum ChangeMap {
    static let maxFiles = 24
    private static let untrackedReadLimit = 512 * 1024

    // MARK: lectura (fuera del hilo principal)

    /// Archivos con cambios, ordenados por tamaño del cambio. Solo `git status` y `git diff --numstat`; no lee contenido
    /// de archivos rastreados. De los nuevos cuenta líneas (con tope de 512 KB) para dar un tamaño honesto.
    static func scan(_ workspace: String) -> [ChangedFile] {
        guard let status = GitPulse.statusRecords(workspace: workspace) else { return [] }
        let numstat = GitPulse.numstat(workspace: workspace)
        var files: [ChangedFile] = []
        for record in status.prefix(400) {
            guard isSafe(record.path) else { continue }
            let url = URL(fileURLWithPath: workspace).appendingPathComponent(record.path)
            let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            if record.status == "??" {
                files.append(ChangedFile(path: record.path, added: countLines(url), deleted: 0, untracked: true,
                                         staged: false, conflict: false, modified: mtime))
            } else {
                let stat = numstat[record.path] ?? (0, 0)
                let staged = record.status.first != " " && record.status.first != "?"
                files.append(ChangedFile(path: record.path, added: stat.0, deleted: stat.1, untracked: false,
                                         staged: staged, conflict: GitPulse.isConflict(record.status), modified: mtime))
            }
        }
        return files.sorted { $0.weight == $1.weight ? $0.path < $1.path : $0.weight > $1.weight }
    }

    static func isSafe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    private static func countLines(_ url: URL) -> Int {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
              let handle = try? FileHandle(forReadingFrom: url) else { return 1 }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: untrackedReadLimit), !data.isEmpty else { return 1 }
        return max(1, data.reduce(0) { $0 + ($1 == 10 ? 1 : 0) })
    }

    // MARK: disposición (pura)

    /// Los `maxFiles` mayores y, si sobran, una celda final que agrupa el resto con su peso real.
    static func cells(_ files: [ChangedFile]) -> (shown: [ChangedFile], rest: Int, restWeight: Double) {
        let shown = Array(files.prefix(maxFiles))
        let rest = files.dropFirst(maxFiles)
        return (shown, rest.count, rest.reduce(0) { $0 + $1.weight })
    }

    /// Treemap "squarified": áreas proporcionales a los pesos (que deben llegar de mayor a menor).
    static func layout(_ weights: [Double], in rect: CGRect) -> [CGRect] {
        let total = weights.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }
        let areas = weights.map { $0 / total * Double(rect.width * rect.height) }
        func worst(_ row: [Double], _ side: Double) -> Double {
            let sum = row.reduce(0, +)
            guard let hi = row.max(), let lo = row.min(), sum > 0, lo > 0 else { return .infinity }
            return max(side * side * hi / (sum * sum), sum * sum / (side * side * lo))
        }
        var out: [CGRect] = []
        var free = rect
        var i = 0
        while i < areas.count {
            let side = Double(min(free.width, free.height))
            var row = [areas[i]]
            var j = i + 1
            while j < areas.count, worst(row + [areas[j]], side) <= worst(row, side) { row.append(areas[j]); j += 1 }
            let sum = row.reduce(0, +)
            if free.width >= free.height {
                let w = CGFloat(sum / Double(free.height))
                var y = free.minY
                for a in row { let h = CGFloat(a) / w; out.append(CGRect(x: free.minX, y: y, width: w, height: h)); y += h }
                free = CGRect(x: free.minX + w, y: free.minY, width: max(0, free.width - w), height: free.height)
            } else {
                let h = CGFloat(sum / Double(free.width))
                var x = free.minX
                for a in row { let w = CGFloat(a) / h; out.append(CGRect(x: x, y: free.minY, width: w, height: h)); x += w }
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: max(0, free.height - h))
            }
            i = j
        }
        return out
    }

    /// Brillo según lo reciente del archivo: 0.9 en los últimos 2 min, bajando hasta 0.3 a partir de 30 min.
    static func brightness(modified: Date?, now: Date) -> Double {
        guard let modified else { return 0.4 }
        let age = max(0, now.timeIntervalSince(modified))
        if age <= 120 { return 0.9 }
        if age >= 1800 { return 0.3 }
        return 0.9 - 0.6 * (age - 120) / (1800 - 120)
    }
}

struct ChangeMapView: View {
    let files: [ChangedFile]
    var title = "mapa de cambios"
    let open: (ChangedFile) -> Void

    private let accent = Color(hex: 0x7DB4FF)
    private let alert = Color(hex: 0xFF8A7A)

    var body: some View {
        let split = ChangeMap.cells(files)
        let weights = split.shown.map(\.weight) + (split.rest > 0 ? [max(1, split.restWeight)] : [])
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Pal.cream.opacity(0.5))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("tamaño = líneas · brillo = reciente").font(.caption2).foregroundStyle(Pal.cream.opacity(0.4))
            }
            GeometryReader { geo in
                let rects = ChangeMap.layout(weights, in: CGRect(origin: .zero, size: geo.size))
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                            if index < split.shown.count {
                                cell(split.shown[index], rect: rect, now: ctx.date)
                            } else {
                                restCell(count: split.rest, rect: rect)
                            }
                        }
                    }
                }
            }
            .frame(height: 132)
        }
    }

    private func tint(_ f: ChangedFile) -> Color {
        f.conflict ? alert : (f.untracked ? Pal.cream : (f.staged ? Color(hex: 0x67D6A3) : accent))
    }

    private func cell(_ f: ChangedFile, rect: CGRect, now: Date) -> some View {
        let level = ChangeMap.brightness(modified: f.modified, now: now)
        let inner = rect.insetBy(dx: 1.5, dy: 1.5)
        let radius = min(6, min(inner.width, inner.height) / 3)
        let roomy = inner.width > 70 && inner.height > 28
        return Button { open(f) } label: {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [tint(f).opacity(level * 0.55), tint(f).opacity(level * 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(tint(f).opacity(level * 0.7), lineWidth: 0.75) }
                .overlay(alignment: .topLeading) {
                    if roomy {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.name).font(.caption.weight(.medium)).lineLimit(1)
                            if inner.height > 44 {
                                Text(f.untracked ? "nuevo · \(f.added) líneas" : "+\(f.added) −\(f.deleted)")
                                    .font(.caption2).foregroundStyle(Pal.cream.opacity(0.7)).lineLimit(1)
                            }
                        }
                        .foregroundStyle(Pal.cream).padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: max(0, inner.width), height: max(0, inner.height))
        .offset(x: inner.minX, y: inner.minY)
        .help(f.path)
        .accessibilityLabel("\(f.path), \(f.untracked ? "archivo nuevo, \(f.added) líneas" : "\(f.added) añadidas, \(f.deleted) borradas")\(f.staged ? ", preparado" : "")\(f.conflict ? ", en conflicto" : "")")
    }

    private func restCell(count: Int, rect: CGRect) -> some View {
        let inner = rect.insetBy(dx: 1.5, dy: 1.5)
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white.opacity(0.05))
            .overlay { if inner.width > 40 && inner.height > 20 { Text("+\(count)").font(.caption2).foregroundStyle(Pal.cream.opacity(0.6)) } }
            .frame(width: max(0, inner.width), height: max(0, inner.height))
            .offset(x: inner.minX, y: inner.minY)
            .accessibilityLabel("\(count) archivos más")
    }
}
