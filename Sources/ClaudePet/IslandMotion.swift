import SwiftUI

enum IslandMotion {
    static let springResponse: Double = 0.42
    static let springDamping: Double = 0.82
    static let maximumDuration: Double = 0.72
    static let stagger: Double = 0.045

    static var spring: Animation { .spring(response: springResponse, dampingFraction: springDamping) }
    static var reduced: Animation { .easeOut(duration: 0.12) }
}
