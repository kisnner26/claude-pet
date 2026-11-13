import SwiftUI

enum IslandMotion {
    static let springResponse: Double = 0.46
    static let springDamping: Double = 0.9
    static let maximumDuration: Double = 0.72
    static let stagger: Double = 0.045

    /// Rebase maximo de un resorte subamortiguado como fraccion del recorrido: e^(-pi z / raiz(1 - z^2)).
    static func overshoot(damping z: Double) -> Double { z >= 1 ? 0 : exp(-.pi * z / (1 - z * z).squareRoot()) }
    /// Tiempo aproximado en quedar a menos del 2 % del destino: 4 / (z * wn), con wn = 2 pi / respuesta.
    static func settleTime(response: Double, damping z: Double) -> Double { 4 / (z * 2 * .pi / response) }
    /// Deslizamiento de la linea de contexto: amortiguacion critica, llega sin pasarse.
    static var slide: Animation { .spring(response: 0.6, dampingFraction: 1) }

    static var spring: Animation { .spring(response: springResponse, dampingFraction: springDamping) }
    static var reduced: Animation { .easeOut(duration: 0.12) }
}
