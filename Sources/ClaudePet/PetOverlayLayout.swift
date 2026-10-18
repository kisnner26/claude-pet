import Foundation

enum PetOverlayLayout {
    static let canvasSize = CGSize(width: 128, height: 128)
    static let ringRadius = 54.0
    static let maximumOrbitFiles = 12

    static func orbitItems(_ files: [ChangedFile], size: CGSize = canvasSize) -> [FileOrbitItem] {
        let shown = Array(files.prefix(maximumOrbitFiles))
        guard !shown.isEmpty else { return [] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.44
        let maximumWeight = shown.map(\.weight).max() ?? 1
        return shown.enumerated().map { index, file in
            // Deja libre la parte superior para el porcentaje de contexto.
            let progress = shown.count == 1 ? 0.5 : Double(index) / Double(shown.count - 1)
            let angle = (-55 + progress * 290) * .pi / 180
            let scale = sqrt(file.weight / maximumWeight)
            let side = 6 + 8 * scale
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            return FileOrbitItem(file: file,
                                 rect: CGRect(x: point.x - side / 2, y: point.y - side / 2,
                                              width: side, height: side))
        }
    }

    static func file(at point: CGPoint, files: [ChangedFile], size: CGSize = canvasSize) -> ChangedFile? {
        orbitItems(files, size: size).reversed().first(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(point) })?.file
    }

    static func hitsContextRing(_ point: CGPoint, size: CGSize = canvasSize) -> Bool {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let distance = hypot(point.x - center.x, point.y - center.y)
        return distance >= ringRadius - 7 && distance <= ringRadius + 7
    }
}
