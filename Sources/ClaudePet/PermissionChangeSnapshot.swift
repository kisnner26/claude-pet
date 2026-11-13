import SwiftUI
import AppKit

extension IslandSnapshot {
    /// `ClaudePet --snapshot-permission-diff <ruta.png>`: la isla con un permiso que trae su cambio, plegado y desplegado
    /// (Edit, MultiEdit, Write nuevo, Write enorme recortado, NotebookEdit y una credencial). Escribe `<ruta>-<escena>.png`.
    /// Los cambios son inventados; no se lee ningun archivo del disco ni se toca el perimetro real.
    @MainActor static func permissionDiff(to path: String) {
        let store = PetStore.shared
        let previousState = store.state
        isRendering = true
        PerimeterStore.shared.storagePath = nil
        defer { isRendering = false; store.permissionAsks = []; store.permissionDiffOpenID = nil; store.setSnapshotState(previousState) }
        let m = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeTop: 0, auxLeft: 0, auxRight: 0)
        let notched = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 38, auxLeft: 664, auxRight: 664)

        func part(_ s: String, omitted: Int = 0) -> ChangePart { ChangePart(text: s, omitted: omitted) }
        func request(_ kind: ChangeRequest.Kind, _ path: String, edits: [(String, String)] = [], content: String? = nil, omitted: Int = 0, mode: String = "") -> ChangeRequest {
            var r = ChangeRequest(kind: kind, path: path)
            r.edits = edits.map { (part($0.0), part($0.1)) }
            if let content { r.content = part(content, omitted: omitted) }
            r.cellMode = mode
            return r
        }
        func ask(_ tool: String, _ path: String, _ change: ChangeDiff) -> PermissionAsk {
            var a = PermissionAsk(id: "diff-demo", session: "abc", tool: tool, project: "mi-app", detail: path, canAlways: true, at: Date())
            a.change = change
            return a
        }

        let root = "/Users/demo/mi-app/"
        let oldFn = """
        func charge(_ order: Order) async throws -> Receipt {
            let amount = order.total
            guard amount > 0 else { throw BillingError.empty }
            let receipt = try await gateway.capture(amount)
            log.info("cobrado \\(amount)")
            return receipt
        }
        """
        let newFn = """
        func charge(_ order: Order) async throws -> Receipt {
            let amount = order.total + order.tax
            guard amount > 0 else { throw BillingError.empty }
            guard !order.isRefunded else { throw BillingError.refunded }
            let receipt = try await gateway.capture(amount, idempotencyKey: order.id)
            log.info("cobrado \\(amount)")
            return receipt
        }
        """
        let edit = ChangeWire.build(request(.edit, root + "Sources/Billing/Charge.swift", edits: [(oldFn, newFn)]))
        let multi = ChangeWire.build(request(.multi, root + "Sources/Billing/Charge.swift", edits: [
            ("let retries = 3", "let retries = 5"), ("timeout: 10", "timeout: 30"),
            ("func charge(_ order: Order)", "func charge(_ order: Order, dryRun: Bool = false)")]))
        let fresh = (0..<48).map { i -> String in
            switch i {
            case 0: return "import Foundation"
            case 2: return "/// Reintenta con espera exponencial; esta linea es muy larga para comprobar como se corta en la tarjeta: " + String(repeating: "abcdefghij ", count: 30)
            case 3: return "enum Retry {"
            case 4: return "\tstatic let base: TimeInterval = 0.5 // con un tabulador al principio"
            default: return "    static func step\(i)(_ n: Int) -> Int { n * \(i) }"
            }
        }.joined(separator: "\n")
        let write = ChangeWire.build(request(.write, root + "Sources/Billing/Retry.swift", content: fresh), base: .missing)
        let huge = ChangeWire.build(request(.write, root + "Sources/Generated/Schema.swift", content: (0..<900).map { "    case field\($0) = \"field_\($0)\"" }.joined(separator: "\n"), omitted: 5200), base: .unreadable)
        let leaky = ChangeWire.build(request(.write, root + "Sources/Billing/Keys.swift", content: "enum Keys {\n    static let live = \"sk-live-4eC39HqLyjWDarjtT1zdp7dc\"\n    static let region = \"eu\"\n}"), base: .missing)
        let nb = ChangeWire.build(request(.notebook, root + "analysis.ipynb", content: "df = pd.read_csv('ventas.csv')\ndf.groupby('mes').total.sum().plot()", mode: "replace"))

        let scenes: [(String, PermissionAsk, Bool, Bool)] = [
            ("edit-plegado", ask("Edit", root + "Sources/Billing/Charge.swift", edit), false, false),
            ("edit-abierto", ask("Edit", root + "Sources/Billing/Charge.swift", edit), true, false),
            ("edit-abierto-notch", ask("Edit", root + "Sources/Billing/Charge.swift", edit), true, true),
            ("multiedit-abierto", ask("MultiEdit", root + "Sources/Billing/Charge.swift", multi), true, false),
            ("write-nuevo-abierto", ask("Write", root + "Sources/Billing/Retry.swift", write), true, false),
            ("write-enorme-abierto", ask("Write", root + "Sources/Generated/Schema.swift", huge), true, false),
            ("secreto-abierto", ask("Write", root + "Sources/Billing/Keys.swift", leaky), true, false),
            ("notebook-plegado", ask("NotebookEdit", root + "analysis.ipynb", nb), false, false),
        ]
        let base = path.hasSuffix(".png") ? String(path.dropLast(4)) : path
        for (name, a, open, notch) in scenes {
            let model = IslandModel()
            let metrics = notch ? notched : m
            model.mode = .expanded; model.placement = .top; model.hasNotch = notch
            store.setSnapshotState(.waiting)
            store.permissionAsks = [a]
            store.permissionDiffOpenID = open ? a.id : nil
            model.size = NotchGeometry.islandSize(.expanded, metrics: metrics, placement: .top, expandedHeight: store.permissionCardHeight)
            let view = IslandView(model: model, store: store)
                .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
                .background(Color(hex: 0x6C7A89))
            let r = ImageRenderer(content: view)
            r.scale = scale
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: "\(base)-\(name).png"))
        }
    }
}
