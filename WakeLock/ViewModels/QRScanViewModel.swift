import Foundation
import AVFoundation
import Combine

enum QRScanMode {
    case setup(label: String)   // registering a new QR code
    case dismiss                 // dismissing an active alarm
}

enum QRScanResult: Equatable {
    case idle
    case scanning
    case success(String)
    case failure(String)
    case permissionDenied
}

final class QRScanViewModel: ObservableObject {

    @Published var result: QRScanResult = .idle
    @Published var cameraPermissionGranted: Bool = false

    let mode: QRScanMode
    var onSuccess: ((String) -> Void)?   // passes the scanned value

    init(mode: QRScanMode) {
        self.mode = mode
        checkCameraPermission()
    }

    // MARK: - Permission

    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraPermissionGranted = granted
                    if !granted { self?.result = .permissionDenied }
                }
            }
        default:
            cameraPermissionGranted = false
            result = .permissionDenied
        }
    }

    // MARK: - Called by scanner view when a code is detected

    func handleScanned(value: String) {
        switch mode {
        case .setup:
            // Any scanned value is valid for setup
            result = .success(value)
            onSuccess?(value)

        case .dismiss:
            // Validate against stored QRs
            if let label = QRManager.shared.validate(scanned: value) {
                result = .success("Matched: \(label)")
                onSuccess?(value)
            } else {
                result = .failure("Wrong QR code. Try again.")
                // Reset after 2s so user can retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.result = .scanning
                }
            }
        }
    }
}
