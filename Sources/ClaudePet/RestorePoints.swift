import Foundation

/// Puntos de restauracion con `git stash create`: guardan el estado de los archivos seguidos en una referencia
/// bajo refs/claude-pet/ sin tocar el arbol de trabajo, el indice ni la pila de stashes. Restaurar solo reescribe
/// archivos seguidos con su contenido del punto; nunca hace reset ni clean, y no toca archivos nuevos.
enum RestorePoints {
    static let maxPerProject = 20
    static let refPrefix = "refs/claude-pet/"

    struct Point: Equatable, Identifiable {
        let ref: String
        let sha: String
        let at: Date
        let label: String
        var id: String { ref }
    }

    private static func git(_ workspace: String, _ args: [String], timeout: TimeInterval = 5) -> (text: String, status: Int32)? {
        let base = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", workspace]
        guard let r = GitPulse.run(arguments: base + args, timeout: timeout) else { return nil }
        return (String(decoding: r.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines), r.status)
    }

    static func isRepo(_ workspace: String) -> Bool {
        !workspace.isEmpty && git(workspace, ["rev-parse", "--is-inside-work-tree"])?.text == "true"
    }

    /// Hay cambios en archivos seguidos que se perderian sin un punto.
    static func isDirty(_ workspace: String) -> Bool {
        guard isRepo(workspace), let r = git(workspace, ["status", "--porcelain=v1", "--untracked-files=no"]) else { return false }
        return !r.text.isEmpty
    }

    private static func slug(_ label: String) -> String {
        let cleaned = label.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(String(cleaned).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-").prefix(24))
    }

    /// Crea un punto si hay cambios que guardar. Devuelve nil si el arbol esta limpio o algo falla.
    @discardableResult
    static func create(workspace: String, label: String, now: Date = Date()) -> Point? {
        guard isRepo(workspace), let made = git(workspace, ["stash", "create"]), made.status == 0, made.text.count >= 40,
              made.text.allSatisfy({ $0.isHexDigit }) else { return nil }
        let stamp = Int(now.timeIntervalSince1970 * 1000)
        let ref = "\(refPrefix)\(stamp)-\(slug(label.isEmpty ? "punto" : label))"
        guard git(workspace, ["update-ref", ref, made.text])?.status == 0 else { return nil }
        prune(workspace: workspace)
        return Point(ref: ref, sha: made.text, at: now, label: label)
    }

    static func list(workspace: String) -> [Point] {
        guard isRepo(workspace), let r = git(workspace, ["for-each-ref", "--format=%(refname) %(objectname)", refPrefix]) else { return [] }
        return r.text.split(separator: "\n").compactMap { line -> Point? in
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { return nil }
            let ref = String(parts[0]), name = ref.dropFirst(refPrefix.count)
            let pieces = name.split(separator: "-", maxSplits: 1)
            guard let ms = Double(pieces.first ?? ""), String(parts[1]).allSatisfy({ $0.isHexDigit }) else { return nil }
            return Point(ref: ref, sha: String(parts[1]), at: Date(timeIntervalSince1970: ms / 1000), label: pieces.count > 1 ? String(pieces[1]) : "")
        }.sorted { $0.at > $1.at }
    }

    static func prune(workspace: String, keep: Int = maxPerProject) {
        for old in list(workspace: workspace).dropFirst(keep) { _ = git(workspace, ["update-ref", "-d", old.ref]) }
    }

    /// Lo que restaurar cambiaria ahora mismo, para mostrarlo antes de pedir confirmacion.
    static func preview(workspace: String, point: Point) -> String {
        guard let r = git(workspace, ["diff", "--stat", "--no-ext-diff", "--no-textconv", point.sha], timeout: 10) else { return "" }
        return r.text.isEmpty ? "el arbol ya coincide con el punto" : r.text
    }

    /// Reescribe los archivos seguidos con su contenido del punto. No toca el indice ni los archivos nuevos.
    @discardableResult
    static func restore(workspace: String, point: Point) -> Bool {
        guard isRepo(workspace), list(workspace: workspace).contains(where: { $0.sha == point.sha }) else { return false }
        return git(workspace, ["restore", "--source=\(point.sha)", "--worktree", "--", ":/"], timeout: 20)?.status == 0
    }
}

import AppKit

/// Dialogo de confirmacion: muestra que cambiaria y solo restaura si el usuario acepta.
enum RestoreDialog {
    @MainActor static func confirm(store: PetStore, point: RestorePoints.Point) {
        let workspace = store.mission.workspace
        let alert = NSAlert()
        alert.messageText = "restaurar el punto de \(point.at.formatted(date: .abbreviated, time: .shortened))"
        alert.informativeText = "esto reescribe los archivos seguidos con su contenido de entonces. los archivos nuevos y el indice no se tocan.\n\n" + String(RestorePoints.preview(workspace: workspace, point: point).prefix(900))
        alert.addButton(withTitle: "cancelar")
        alert.addButton(withTitle: "restaurar")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        if !RestorePoints.restore(workspace: workspace, point: point) { NSSound.beep() }
    }
}
