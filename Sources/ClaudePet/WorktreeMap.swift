import AppKit
import Foundation
import SwiftUI

struct WorktreeNode: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let branch: String
    let revision: String
    let current: Bool
    let locked: Bool
    let dirty: Bool
    let conflicts: Int

    var title: String { branch.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : branch }
}

enum WorktreeMap {
    static let limit = 8

    static func parse(_ text: String, currentPath: String) -> [WorktreeNode] {
        text.components(separatedBy: "\n\n").compactMap { block in
            var path = "", branch = "", revision = ""
            var locked = false
            for line in block.split(separator: "\n").map(String.init) {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst(9)) }
                else if line.hasPrefix("branch refs/heads/") { branch = String(line.dropFirst(18)) }
                else if line.hasPrefix("HEAD ") { revision = String(line.dropFirst(5).prefix(8)) }
                else if line == "locked" || line.hasPrefix("locked ") { locked = true }
            }
            guard !path.isEmpty else { return nil }
            return WorktreeNode(path: path, branch: branch, revision: revision,
                                current: URL(fileURLWithPath: path).standardized.path == URL(fileURLWithPath: currentPath).standardized.path,
                                locked: locked, dirty: false, conflicts: 0)
        }
    }

    static func scan(_ workspace: String) -> [WorktreeNode] {
        guard let result = GitPulse.run(arguments: ["-C", workspace, "worktree", "list", "--porcelain"], timeout: 5, limit: 64 * 1024),
              result.status == 0 else { return [] }
        return parse(String(decoding: result.data, as: UTF8.self), currentPath: workspace).prefix(limit).map { node in
            let health = GitPulse.scan(node.path, timeout: 4)
            return WorktreeNode(path: node.path, branch: node.branch, revision: node.revision,
                                current: node.current, locked: node.locked,
                                dirty: health.affected > 0, conflicts: health.conflicts)
        }
    }

    static func positions(count: Int, size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if count == 1 { return [center] }
        let radius = min(size.width * 0.42, size.height * 0.35)
        return (0..<count).map { index in
            let angle = -Double.pi / 2 + Double(index) / Double(count) * Double.pi * 2
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }
}

struct BranchWebView: View {
    let nodes: [WorktreeNode]
    let open: (WorktreeNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("telaraña de ramas").font(.caption.weight(.semibold)).foregroundStyle(Pal.cream.opacity(0.5))
                Spacer()
                Text("\(nodes.count) worktrees").font(.caption2.monospacedDigit()).foregroundStyle(Pal.cream.opacity(0.45))
            }
            GeometryReader { geo in
                let positions = WorktreeMap.positions(count: nodes.count, size: geo.size)
                ZStack {
                    Canvas { context, _ in
                        guard let current = nodes.firstIndex(where: \.current), current < positions.count else { return }
                        for index in nodes.indices where index != current && index < positions.count {
                            var line = Path()
                            line.move(to: positions[current]); line.addLine(to: positions[index])
                            context.stroke(line, with: .color(nodes[index].conflicts > 0 ? Color(hex: 0xFF8A7A) : Color.white.opacity(0.18)),
                                           style: StrokeStyle(lineWidth: nodes[index].dirty ? 2 : 1,
                                                              dash: nodes[index].locked ? [3, 3] : []))
                        }
                    }
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        Button { open(node) } label: {
                            VStack(spacing: 3) {
                                Circle()
                                    .fill(node.conflicts > 0 ? Color(hex: 0xFF8A7A) : (node.current ? Color(hex: 0x7DB4FF) : Pal.cream.opacity(0.72)))
                                    .frame(width: node.current ? 13 : 9, height: node.current ? 13 : 9)
                                    .overlay { if node.dirty { Circle().stroke(Pal.charcoal, lineWidth: 2) } }
                                Text(node.title).font(.caption2).foregroundStyle(Pal.cream).lineLimit(1)
                            }
                            .frame(width: 100)
                        }
                        .buttonStyle(.plain)
                        .position(positions[index])
                        .help(node.path)
                        .accessibilityLabel("rama \(node.title)\(node.current ? ", actual" : "")\(node.dirty ? ", con cambios" : "")\(node.conflicts > 0 ? ", con conflictos" : "")")
                    }
                }
            }
            .frame(height: 112)
        }
    }
}
