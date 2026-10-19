import Foundation
import SwiftUI

struct DiffPull: Equatable {
    struct Line: Equatable {
        enum Kind { case added, removed, context }
        let text: String
        let kind: Kind
    }
    let file: ChangedFile
    let lines: [Line]
}

enum DiffPullReader {
    static func read(workspace: String, file: ChangedFile) -> DiffPull? {
        guard ChangeMap.isSafe(file.path) else { return nil }
        if file.untracked {
            let root = URL(fileURLWithPath: workspace).standardizedFileURL
            let url = root.appendingPathComponent(file.path).standardizedFileURL
            guard url.path.hasPrefix(root.path + "/"), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return DiffPull(file: file, lines: text.split(separator: "\n").prefix(5).map { .init(text: String($0.prefix(70)), kind: .added) })
        }
        let arguments = ["-C", workspace, "-c", "core.fsmonitor=false", "-c", "core.pager=cat", "diff", "HEAD",
                         "--no-ext-diff", "--no-textconv", "--no-color", "--unified=1", "--", file.path]
        guard let result = GitPulse.run(arguments: arguments, timeout: 5, limit: 64 * 1024), result.status == 0 else { return nil }
        let lines = String(decoding: result.data, as: UTF8.self).split(separator: "\n").compactMap { raw -> DiffPull.Line? in
            let text = String(raw)
            guard !text.hasPrefix("+++") && !text.hasPrefix("---") && !text.hasPrefix("@@") && !text.hasPrefix("diff ") && !text.hasPrefix("index ") else { return nil }
            if text.hasPrefix("+") { return .init(text: String(text.dropFirst().prefix(70)), kind: .added) }
            if text.hasPrefix("-") { return .init(text: String(text.dropFirst().prefix(70)), kind: .removed) }
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .init(text: String(text.prefix(70)), kind: .context)
        }
        return DiffPull(file: file, lines: Array(lines.prefix(5)))
    }
}

struct DiffPullView: View {
    let pull: DiffPull

    var body: some View {
        Canvas { context, _ in
            var tether = Path()
            tether.move(to: CGPoint(x: 74, y: 69))
            tether.addCurve(to: CGPoint(x: 112, y: 86), control1: CGPoint(x: 88, y: 62), control2: CGPoint(x: 96, y: 91))
            context.stroke(tether, with: .color(Pal.cream.opacity(0.55)), lineWidth: 1.5)
            for (index, line) in pull.lines.prefix(4).enumerated() {
                let width = CGFloat(min(28, max(8, line.text.count / 2)))
                let rect = CGRect(x: 96 - width / 2, y: 83 + CGFloat(index * 5), width: width, height: 2)
                let color: Color = line.kind == .added ? Color(hex: 0x67D6A3) : (line.kind == .removed ? Color(hex: 0xFF8A7A) : Pal.cream.opacity(0.5))
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .frame(width: 128, height: 128)
        .accessibilityHidden(true)
    }
}
