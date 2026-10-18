import SwiftUI

struct FileOrbitView: View {
    let files: [ChangedFile]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Canvas { graphics, size in
                for item in PetOverlayLayout.orbitItems(files, size: size) {
                    draw(item, in: &graphics, now: context.date)
                }
            }
        }
        .frame(width: PetOverlayLayout.canvasSize.width, height: PetOverlayLayout.canvasSize.height)
        .accessibilityHidden(true)
    }

    private func draw(_ item: FileOrbitItem, in graphics: inout GraphicsContext, now: Date) {
        let file = item.file
        let tint = color(for: file)
        let brightness = ChangeMap.brightness(modified: file.modified, now: now)
        let shape = Path(roundedRect: item.rect, cornerRadius: min(3, item.rect.width / 4))
        graphics.fill(shape, with: .color(tint.opacity(0.35 + brightness * 0.45)))
        graphics.stroke(shape, with: .color(tint.opacity(0.9)), lineWidth: file.staged || file.conflict ? 1.5 : 1)

        if file.untracked {
            graphics.stroke(shape, with: .color(Pal.charcoal.opacity(0.9)),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        } else if file.conflict {
            var cross = Path()
            cross.move(to: CGPoint(x: item.rect.minX + 3, y: item.rect.minY + 3))
            cross.addLine(to: CGPoint(x: item.rect.maxX - 3, y: item.rect.maxY - 3))
            cross.move(to: CGPoint(x: item.rect.maxX - 3, y: item.rect.minY + 3))
            cross.addLine(to: CGPoint(x: item.rect.minX + 3, y: item.rect.maxY - 3))
            graphics.stroke(cross, with: .color(Pal.charcoal), lineWidth: 1.4)
        } else if file.staged {
            let bar = CGRect(x: item.rect.minX + 2, y: item.rect.minY + 2,
                             width: max(1, item.rect.width - 4), height: 2)
            graphics.fill(Path(bar), with: .color(Pal.charcoal.opacity(0.8)))
        }
    }

    private func color(for file: ChangedFile) -> Color {
        if file.conflict { return Color(hex: 0xFF6B63) }
        if file.untracked { return Pal.cream }
        if file.staged { return Color(hex: 0x67D6A3) }
        return Color(hex: 0x7DB4FF)
    }
}
