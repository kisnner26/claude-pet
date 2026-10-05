import SwiftUI

/// Lo que el escenario necesita saber para dibujar a Codex junto a Claude.
struct CompanionInfo: Equatable {
    var codex: PetState
    var claude: PetState
    var codexCheer: Bool      // Codex acaba de terminar
    var codexConcern: Bool    // Codex acaba de fallar
    var claudeDone: Bool      // Claude acaba de terminar
}

/// Pose de Codex en un instante. Funcion pura: mismo (info, t, motion) -> misma pose.
struct CompanionPose: Equatable {
    var face: CodexAvatar.Face = .prompt(cursor: true)
    var legs: CodexAvatar.Legs = .stand
    var emote: CodexAvatar.Emote?
    var hop = 0.0          // px hacia arriba
    var bob = 0.0          // px; negativo = sube
    var shake = 0.0        // px horizontales

    /// - Parameter motion: false con "reducir movimiento" o animaciones apagadas: misma cara, sin saltos ni vaiven.
    static func make(info: CompanionInfo, t: Double, motion: Bool) -> CompanionPose {
        func phase(_ hz: Double) -> Int { Int(max(0, t) * hz) }
        var p = CompanionPose()
        switch info.codex {
        case .idle:
            p.face = .prompt(cursor: !motion || phase(2) % 2 == 0)
            if info.claudeDone {                                   // choque de manos: Claude termino
                p.face = .happy; p.emote = .check
                if motion && phase(4) % 2 == 0 { p.hop = 8 }
            } else {
                switch info.claude {                               // atencion a lo que hace Claude
                case .thinking, .tool, .starting: p.emote = .dots(motion ? 1 + phase(2.5) % 3 : 3)
                case .waiting: p.emote = .bang
                case .error: p.emote = .question
                default: break
                }
            }
        case .starting: p.face = .dots(motion ? phase(3) % 4 : 3)
        case .thinking:
            p.face = .dots(motion ? 1 + phase(2.5) % 3 : 3)
            if motion && phase(2) % 2 == 1 { p.bob = -2 }
        case .tool:
            p.face = .typing(motion ? phase(6) : 0)
            if motion { let s = phase(6) % 2 == 0; p.bob = s ? 0 : -2; p.legs = s ? .step : .stand }
        case .waiting:
            p.face = .alert(on: !motion || phase(3) % 2 == 0)
            if motion { let ph = t * 1.1 - (t * 1.1).rounded(.down); if ph < 0.18 { p.hop = 8 } }
        case .done:
            p.face = .happy
            if motion && info.codexCheer && phase(4) % 2 == 0 { p.hop = 10 }
        case .error:
            p.face = .cross
            if motion { p.shake = phase(14) % 2 == 0 ? 2 : -2 }
        }
        return p
    }
}

/// Quien esta en uso. Claude: su app abierta o una sesion de Claude Code con hooks. Codex: su app abierta o su adaptador en el bus.
struct Presence: Equatable { var claude: Bool; var codex: Bool }

enum PresenceLogic {
    /// Cada mascota es una ventana independiente: aparecen y se mueven por separado.
    struct Visibility: Equatable {
        var claudeWindow: Bool
        var codexWindow: Bool
    }

    static func presence(claudeAppOpen: Bool, hookSessionActive: Bool, codexAppOpen: Bool, peerPresent: Bool) -> Presence {
        Presence(claude: claudeAppOpen || hookSessionActive, codex: codexAppOpen || peerPresent)
    }

    /// - auto: cada mascota aparece solo si su herramienta esta en uso. Apagado: Claude siempre, Codex si esta presente.
    /// - userHidden: el usuario oculto todo desde el menu.
    static func visibility(_ p: Presence, auto: Bool, userHidden: Bool) -> Visibility {
        if userHidden { return Visibility(claudeWindow: false, codexWindow: false) }
        return Visibility(claudeWindow: auto ? p.claude : true, codexWindow: p.codex)
    }
}

enum CompanionLogic {
    /// Hacia donde mira Claude: hacia Codex cuando este trabaja y Claude esta en reposo.
    /// -1 = izquierda (escenario normal), +1 = derecha (escenario reflejado). 0 = no mira.
    static func lookX(peer: PetState?, claude: PetState, mirrored: Bool) -> Int {
        guard let peer, claude == .idle, peer == .thinking || peer == .tool || peer == .waiting else { return 0 }
        return mirrored ? 1 : -1
    }
}

/// Datos para dibujar el partido entre las dos ventanas (coordenadas de la capa del partido, origen arriba a la izquierda).
struct GameGeometry: Equatable {
    var stageFrame: CGRect        // en pantalla (origen abajo a la izquierda): la capa cubre a las dos mascotas y el arco
    var ballStart: CGPoint        // esquina superior izquierda de la pelota en reposo, junto al pie de Codex
    var ballEnd: CGPoint          // idem, sobre la cabeza de Claude
    var groundStart: CGFloat      // linea del suelo bajo Codex / bajo Claude
    var groundEnd: CGFloat
    var facing: Int               // +1: Claude esta a la derecha de Codex; -1: a la izquierda
    var size: CGSize { stageFrame.size }
}

enum GameLayout {
    /// Calcula la capa del partido a partir de las posiciones reales de las dos ventanas.
    /// `nil` si estan demasiado lejos para jugar. Las ventanas nunca se mueven por el partido.
    static func make(claude: CGRect, codex: CGRect) -> GameGeometry? {
        let M = StageMetrics.self
        guard abs(claude.midX - codex.midX) <= M.maxPairDX, abs(claude.midY - codex.midY) <= M.maxPairDY else { return nil }
        let facing = claude.midX >= codex.midX ? 1 : -1
        let u = claude.union(codex)
        let stage = CGRect(x: u.minX - M.stageMarginSide, y: u.minY - M.stageMarginBottom,
                           width: u.width + 2 * M.stageMarginSide, height: u.height + M.stageMarginBottom + M.stageMarginTop)
        func sx(_ x: CGFloat) -> CGFloat { x - stage.minX }
        func sy(_ y: CGFloat) -> CGFloat { stage.maxY - y }              // de abajo-izquierda a arriba-izquierda

        let frontFoot = M.avatarLeft + 16 * M.avatarCell + 4              // punta de la pierna al patear
        let startLeft = facing > 0 ? codex.minX + frontFoot : codex.maxX - frontFoot - M.ballSize
        let codexGroundY = codex.maxY - M.codexGround
        let claudeGroundY = claude.minY + M.claudeFeetInset
        let headTopY = claude.maxY - M.claudeHeadTop
        return GameGeometry(
            stageFrame: stage,
            ballStart: CGPoint(x: sx(startLeft), y: sy(codexGroundY + M.ballSize)),
            ballEnd: CGPoint(x: sx(claude.midX - M.ballSize / 2), y: sy(headTopY + M.ballSize)),
            groundStart: sy(codexGroundY), groundEnd: sy(claudeGroundY), facing: facing)
    }
}
