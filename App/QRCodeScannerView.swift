import AVFoundation
import SwiftUI
import UIKit

struct QRCodeScannerView: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            Group {
                switch authorizationStatus {
                case .authorized:
                    QRCodeScannerRepresentable { value in
                        onScan(value)
                        dismiss()
                    }
                    .ignoresSafeArea(edges: .bottom)
                case .notDetermined:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Requesting camera access")
                            .foregroundStyle(.secondary)
                    }
                    .task {
                        await requestAccess()
                    }
                case .denied, .restricted:
                    manualFallback
                @unknown default:
                    manualFallback
                }
            }
            .navigationTitle("Scan Pairing QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var manualFallback: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Camera Access Needed")
                    .font(.headline)

                Text("Enter the server URL and pairing code manually from the previous screen.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Use Manual Entry") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    @MainActor
    private func requestAccess() async {
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }

        authorizationStatus = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .video)
    }
}

private struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        QRCodeScannerViewController(onScan: onScan)
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}

private final class QRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.raph559.waypoint.qr-session")
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let onScan: (String) -> Void
    private var didScan = false
    private var isSessionConfigured = false
    private var isViewActive = false

    init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreview()
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setViewActive(true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setViewActive(false)
    }

    private func configurePreview() {
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isSessionConfigured else {
                return
            }

            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                return
            }

            self.captureSession.beginConfiguration()
            defer {
                self.captureSession.commitConfiguration()
                if self.isSessionConfigured {
                    self.startSessionIfNeeded()
                }
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                guard self.captureSession.canAddInput(videoInput) else {
                    return
                }
                self.captureSession.addInput(videoInput)

                let metadataOutput = AVCaptureMetadataOutput()
                guard self.captureSession.canAddOutput(metadataOutput) else {
                    return
                }
                self.captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                metadataOutput.metadataObjectTypes = [.qr]

                self.isSessionConfigured = true
            } catch {
                return
            }
        }
    }

    private func setViewActive(_ isActive: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.isViewActive = isActive
            if isActive {
                self.startSessionIfNeeded()
            } else {
                self.stopSessionIfNeeded()
            }
        }
    }

    private func startSessionIfNeeded() {
        guard isViewActive, isSessionConfigured, !captureSession.isRunning else {
            return
        }
        captureSession.startRunning()
    }

    private func stopSessionIfNeeded() {
        guard captureSession.isRunning else {
            return
        }
        captureSession.stopRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            !didScan,
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            object.type == .qr,
            let value = object.stringValue
        else {
            return
        }

        didScan = true
        setViewActive(false)
        DispatchQueue.main.async { [onScan] in
            onScan(value)
        }
    }
}
