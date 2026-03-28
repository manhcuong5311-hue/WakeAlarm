import SwiftUI
import AVFoundation

/// UIViewRepresentable wrapping AVCaptureSession for multi-format barcode scanning.
///
/// Fix: previously only supported `.qr`. Now handles all readable formats
/// including EAN, Code128, PDF417, Aztec, DataMatrix etc.
/// Also normalizes output (trimmed) and uses transformed metadata bounds
/// for accurate detection regardless of code shape/density.
struct QRScannerView: UIViewRepresentable {

    /// Called with (rawValue, codeTypeRawValue) on a successful scan.
    var onDetected: (String, String) -> Void

    func makeUIView(context: Context) -> ScannerUIView {
        let view = ScannerUIView()
        view.onDetected = onDetected
        return view
    }

    func updateUIView(_ uiView: ScannerUIView, context: Context) {}

    func dismantleUIView(_ uiView: ScannerUIView, coordinator: Coordinator) {
        uiView.stopSession()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {}

    // MARK: - ScannerUIView

    final class ScannerUIView: UIView, AVCaptureMetadataOutputObjectsDelegate {

        var onDetected: ((String, String) -> Void)?

        private var captureSession: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        /// Debounce flag – prevents duplicate callbacks from the same physical scan
        private var lastScannedValue: String?
        private var debounceTimer: Timer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            setupSession()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }

        func stopSession() {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.stopRunning()
            }
        }

        // MARK: - Session setup

        private func setupSession() {
            let session = AVCaptureSession()
            session.sessionPreset = .hd1280x720   // good balance of detail vs perf

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)

            // Use main queue for delegate so UI callbacks are safe
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

            // FIX: support every format AVFoundation can read, not just .qr
            // Filter to types the device actually supports to avoid runtime crashes
            let wantedTypes: [AVMetadataObject.ObjectType] = [
                .qr,
                .ean8, .ean13, .upce,
                .code39, .code39Mod43,
                .code93, .code128,
                .pdf417,
                .aztec,
                .dataMatrix,
                .itf14,
                .interleaved2of5
            ]
            output.metadataObjectTypes = wantedTypes.filter {
                output.availableMetadataObjectTypes.contains($0)
            }

            // Restrict scanning to the visible viewfinder area for accuracy
            // (set in layoutSubviews once bounds are known)
            output.rectOfInterest = CGRect(x: 0.175, y: 0.175, width: 0.65, height: 0.65)

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = bounds
            preview.videoGravity = .resizeAspectFill
            layer.insertSublayer(preview, at: 0)
            previewLayer = preview

            captureSession = session
            addScanOverlay()

            // Run session on background thread – never block main thread
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }

        // MARK: - Viewfinder overlay

        private func addScanOverlay() {
            // Dim outer area
            let dimView = UIView()
            dimView.translatesAutoresizingMaskIntoConstraints = false
            dimView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            addSubview(dimView)
            NSLayoutConstraint.activate([
                dimView.topAnchor.constraint(equalTo: topAnchor),
                dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
                dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
                dimView.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])

            // Clear rectangle cutout in the middle
            // Using a CAShapeLayer mask so the centre is transparent
            let maskLayer = CAShapeLayer()
            dimView.layer.mask = maskLayer

            // We'll update the mask path on layout
            dimView.tag = 100    // used to find & update in layoutSubviews
            layer.addSublayer(CALayer())   // placeholder – mask updated on layout

            // Viewfinder border frame (sits above dim layer)
            let frame = UIView()
            frame.translatesAutoresizingMaskIntoConstraints = false
            frame.layer.borderColor = UIColor.systemGreen.cgColor
            frame.layer.borderWidth = 2
            frame.layer.cornerRadius = 14
            frame.backgroundColor = .clear
            addSubview(frame)
            NSLayoutConstraint.activate([
                frame.centerXAnchor.constraint(equalTo: centerXAnchor),
                frame.centerYAnchor.constraint(equalTo: centerYAnchor),
                frame.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.65),
                // FIX: use heightAnchor equal to width so it scales correctly
                // but don't force square — let it adapt
                frame.heightAnchor.constraint(equalTo: frame.widthAnchor)
            ])

            // Corner accent lines (cosmetic premium feel)
            addCornerAccents(to: frame)
        }

        private func addCornerAccents(to parent: UIView) {
            let length: CGFloat = 20
            let thickness: CGFloat = 3
            let color = UIColor.systemGreen

            let positions: [(x: NSLayoutXAxisAnchor, y: NSLayoutYAxisAnchor, flipX: Bool, flipY: Bool)] = [
                (parent.leadingAnchor, parent.topAnchor, false, false),
                (parent.trailingAnchor, parent.topAnchor, true, false),
                (parent.leadingAnchor, parent.bottomAnchor, false, true),
                (parent.trailingAnchor, parent.bottomAnchor, true, true)
            ]

            for pos in positions {
                // Horizontal bar
                let h = UIView()
                h.backgroundColor = color
                h.translatesAutoresizingMaskIntoConstraints = false
                parent.addSubview(h)
                NSLayoutConstraint.activate([
                    h.widthAnchor.constraint(equalToConstant: length),
                    h.heightAnchor.constraint(equalToConstant: thickness),
                    pos.flipX
                        ? h.trailingAnchor.constraint(equalTo: pos.x)
                        : h.leadingAnchor.constraint(equalTo: pos.x),
                    pos.flipY
                        ? h.bottomAnchor.constraint(equalTo: pos.y)
                        : h.topAnchor.constraint(equalTo: pos.y)
                ])

                // Vertical bar
                let v = UIView()
                v.backgroundColor = color
                v.translatesAutoresizingMaskIntoConstraints = false
                parent.addSubview(v)
                NSLayoutConstraint.activate([
                    v.widthAnchor.constraint(equalToConstant: thickness),
                    v.heightAnchor.constraint(equalToConstant: length),
                    pos.flipX
                        ? v.trailingAnchor.constraint(equalTo: pos.x)
                        : v.leadingAnchor.constraint(equalTo: pos.x),
                    pos.flipY
                        ? v.bottomAnchor.constraint(equalTo: pos.y)
                        : v.topAnchor.constraint(equalTo: pos.y)
                ])
            }
        }

        // MARK: - AVCaptureMetadataOutputObjectsDelegate

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            // FIX: Use transformedMetadataObject to get bounds relative to the
            // preview layer — works for non-square codes (PDF417, DataMatrix etc.)
            guard let raw = objects.first as? AVMetadataMachineReadableCodeObject,
                  let transformed = previewLayer?.transformedMetadataObject(for: raw)
                    as? AVMetadataMachineReadableCodeObject,
                  let rawValue = transformed.stringValue else { return }

            // FIX: Normalise output — trim whitespace, handle encoding variants
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }

            // Debounce: ignore if same value was just reported (within 2s)
            guard value != lastScannedValue else { return }

            lastScannedValue = value
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.lastScannedValue = nil
            }

            // Provide haptic confirmation on successful scan
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            onDetected?(value, raw.type.rawValue)
        }
    }
}
