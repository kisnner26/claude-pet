import AVFoundation
import SwiftUI

/// Lee el QR de claude pet con la cámara: `visto://pair?c=CODIGO`.
struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String, RelayEndpoint?) -> Void
    func makeUIViewController(context: Context) -> ScannerController { let c = ScannerController(); c.onCode = onCode; return c }
    func updateUIViewController(_ vc: ScannerController, context: Context) {}

    static func code(from text: String) -> String? { payload(from: text)?.code }

    /// `visto://pair?c=CODIGO` y, si la Mac usa un relay, `&r=host:puerto&t=1`.
    static func payload(from text: String) -> (code: String, relay: RelayEndpoint?)? {
        guard let u = URLComponents(string: text), u.scheme == "visto", u.host == "pair", let c = u.queryItems?.first(where: { $0.name == "c" })?.value, Pairing.isValid(c) else { return nil }
        let r = u.queryItems?.first(where: { $0.name == "r" })?.value
        let tls = u.queryItems?.first(where: { $0.name == "t" })?.value == "1"
        return (c, r.flatMap { RelayEndpoint.parse($0, tls: tls) })
    }
}

import VistoCore

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String, RelayEndpoint?) -> Void)?
    private let session = AVCaptureSession()
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else { return }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else { return }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill; layer.frame = view.bounds
        view.layer.addSublayer(layer)
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); view.layer.sublayers?.first?.frame = view.bounds }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); DispatchQueue.global().async { self.session.startRunning() } }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session.stopRunning() }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !done, let s = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, let p = QRScanner.payload(from: s) else { return }
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(p.code, p.relay)
    }
}
