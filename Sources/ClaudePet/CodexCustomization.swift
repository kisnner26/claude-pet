import Foundation

enum CodexSkin: String, CaseIterable {
    case cloud, mint, violet

    var title: String {
        switch self {
        case .cloud: "Nube azul"
        case .mint: "Terminal menta"
        case .violet: "Circuito violeta"
        }
    }
}

enum CodexGesture: String, CaseIterable {
    case wave, salute, celebrate, curious, patrol

    var title: String {
        switch self {
        case .wave: "Saludar"
        case .salute: "Saludo formal"
        case .celebrate: "Celebrar"
        case .curious: "Curiosidad"
        case .patrol: "Patrullar"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .celebrate: 2.5
        case .patrol: 3
        default: 2
        }
    }
}
