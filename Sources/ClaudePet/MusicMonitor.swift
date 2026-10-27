import AppKit

/// Lee solo si Music o Spotify estan reproduciendo, para que la mascota baile. Nunca pide titulos, artistas ni portadas.
/// Es opt-in: la primera consulta hace que macOS pida permiso de automatizacion. Solo pregunta a una app que ya esta abierta,
/// asi que nunca la lanza.
@MainActor
final class MusicMonitor {
    static let pollInterval: TimeInterval = 4
    private var lastPoll: TimeInterval = -100
    private var playing = false

    private static let players: [(bundle: String, script: String)] = [
        ("com.apple.Music", "tell application id \"com.apple.Music\" to return (player state as string)"),
        ("com.spotify.client", "tell application id \"com.spotify.client\" to return (player state as string)"),
    ]

    /// "playing" (o el equivalente en otros idiomas del script) significa que suena.
    nonisolated static func parse(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "playing"
    }

    func isPlaying(enabled: Bool, now: TimeInterval) -> Bool {
        guard enabled else { playing = false; return false }
        guard now - lastPoll >= Self.pollInterval else { return playing }
        lastPoll = now
        playing = Self.players.contains { player in
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == player.bundle }) else { return false }
            var error: NSDictionary?
            let result = NSAppleScript(source: player.script)?.executeAndReturnError(&error)
            return error == nil && Self.parse(result?.stringValue ?? "")
        }
        return playing
    }
}
