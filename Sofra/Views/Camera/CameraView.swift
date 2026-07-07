//
//  CameraView.swift
//  Sofra — root screen, camera-first capture using AVFoundation.
//
//  AVFoundation chosen over PhotosPicker/UIImagePickerController because:
//  1. Full control over the capture moment (shutter animation, haptic timing).
//  2. Direct access to the preview layer for the analysis overlay transition.
//  3. Native-feeling camera UX — the app opens straight into the camera.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - AVFoundation camera preview

/// Custom UIView that keeps its preview layer sized to bounds.
final class PreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet { oldValue?.removeFromSuperlayer() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.layer.insertSublayer(layer, at: 0)
        self.previewLayer = layer
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.backgroundColor = .black
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        view.attach(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // layoutSubviews handles frame resizing
    }
}

// MARK: - Camera manager

final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureContinuation: CheckedContinuation<Data, Error>?

    override init() {
        super.init()
        session.sessionPreset = .photo
    }

    func requestAccess() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func setupCamera() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .back) else {
            throw CameraError.noDevice
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)
    }

    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    func capturePhoto() async throws -> Data {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
        return try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            captureContinuation?.resume(throwing: error)
            captureContinuation = nil
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            captureContinuation?.resume(throwing: CameraError.noData)
            captureContinuation = nil
            return
        }
        captureContinuation?.resume(returning: data)
        captureContinuation = nil
    }
}

enum CameraError: LocalizedError {
    case noDevice, cannotAddInput, cannotAddOutput, noData
    var errorDescription: String? {
        "Kamera başlatılamadı."
    }
}

// MARK: - Main camera view

struct CameraView: View {
    @Environment(NavigationModel.self) private var nav
    @State private var camera = CameraManager()
    @State private var showShutterFlash = false
    @State private var authorized = false
    @State private var setupError = false

    var body: some View {
        ZStack {
            // Camera preview
            if authorized {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Shutter flash overlay
            if showShutterFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Gradient overlay at top/bottom for readability
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.4), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 120)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // UI overlay
            VStack {
                // Top bar
                HStack {
                    // Free scan counter
                    FreeScanBadge()
                    Spacer()
                }
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.top, 60)

                Spacer()

                // Bottom controls
                VStack(spacing: Layout.Spacing.xl) {
                    // Capture button
                    Button {
                        Task { await capture() }
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 76, height: 76)
                            Circle()
                                .fill(.white)
                                .frame(width: 62, height: 62)
                        }
                    }

                    // Text log alternative
                    Button {
                        nav.goToTextLog()
                    } label: {
                        HStack(spacing: Layout.Spacing.xs) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 15))
                            Text("Yazarak ekle")
                                .font(.sofraLabel)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, Layout.Spacing.lg)
                        .padding(.vertical, Layout.Spacing.sm)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .task {
            authorized = await camera.requestAccess()
            if authorized {
                do {
                    try camera.setupCamera()
                    camera.startSession()
                } catch {
                    setupError = true
                }
            }
        }
        .onDisappear {
            camera.stopSession()
        }
    }

    private func capture() async {
        // Haptic + shutter flash
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        withAnimation(.easeOut(duration: 0.06)) { showShutterFlash = true }
        try? await Task.sleep(nanoseconds: 60_000_000) // 60ms
        withAnimation(.easeOut(duration: 0.06)) { showShutterFlash = false }

        do {
            let imageData = try await camera.capturePhoto()
            guard let uiImage = UIImage(data: imageData) else { return }
            nav.startAnalysis(imageData: imageData, uiImage: uiImage)
        } catch {
            // Camera capture failed silently — user can retry
        }
    }
}

// MARK: - Free scan badge

struct FreeScanBadge: View {
    @State private var counter = FreeScanCounter.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: counter.canScanForFree ? "camera.fill" : "lock.fill")
                .font(.system(size: 11))
            Text(counter.canScanForFree
                 ? "\(counter.remainingFreeScans) ücretsiz"
                 : "Limit doldu")
                .font(.sofraCaption)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, Layout.Spacing.md)
        .padding(.vertical, Layout.Spacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
