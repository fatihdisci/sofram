//
//  CameraView.swift
//  Sofra — camera capture screen using AVFoundation.
//
//  AVFoundation chosen over PhotosPicker/UIImagePickerController because:
//  1. Full control over the capture moment (shutter animation, haptic timing).
//  2. Direct access to the preview layer for the analysis overlay transition.
//  3. Native-feeling camera UX — the app opens straight into the camera.
//
//  The manager is a single shared instance: the AVCaptureSession is configured
//  once and started/stopped as the screen comes and goes. All session mutations
//  run on one serial queue, so a stop queued by a disappearing view and a start
//  queued by the next one can never interleave.
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        layer.frame = bounds
        self.layer.insertSublayer(layer, at: 0)
        self.previewLayer = layer
    }
}

struct CameraPreview: UIViewRepresentable {
    let manager: CameraManager

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.backgroundColor = .black
        view.attach(manager.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Re-claim the layer if another PreviewView held it (screen re-entry).
        if uiView.previewLayer !== manager.previewLayer {
            uiView.attach(manager.previewLayer)
        }
    }
}

// MARK: - Camera manager

final class CameraManager: NSObject, @unchecked Sendable {

    /// One camera session for the whole app. Configured once, restarted cheaply.
    static let shared = CameraManager()

    let session = AVCaptureSession()

    /// All session/device mutations are funneled through this serial queue —
    /// start/stop calls from disappearing/appearing screens stay strictly ordered.
    private let sessionQueue = DispatchQueue(label: "com.fatih.sofra.camera.session")

    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<Data, Error>?

    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    private override init() {
        super.init()
        session.sessionPreset = .photo
    }

    var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccess() async -> Bool {
        switch authorizationStatus {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Configures inputs/outputs once; subsequent calls only restart the session.
    func startSession() {
        sessionQueue.async { [self] in
            if !isConfigured {
                do { try configure() } catch { return }
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stopSession() {
        sessionQueue.async { [self] in
            setTorchLocked(false)
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() throws {
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
        self.device = device
        isConfigured = true
    }

    // MARK: Torch

    var hasTorch: Bool { device?.hasTorch ?? false }

    func setTorch(_ on: Bool) {
        sessionQueue.async { [self] in setTorchLocked(on) }
    }

    private func setTorchLocked(_ on: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch { /* torch is best-effort */ }
    }

    // MARK: Focus

    /// Focus/expose at a point given in preview-layer coordinates.
    func focus(atLayerPoint point: CGPoint) {
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async { [self] in
            guard let device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch { /* focus is best-effort */ }
        }
    }

    // MARK: Capture

    /// The continuation is registered on the session queue *before*
    /// `capturePhoto` is invoked, so a fast-failing delegate callback can never
    /// observe a nil continuation (the old implementation had that race and a
    /// failed capture would hang the shutter button forever).
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard session.isRunning else {
                    continuation.resume(throwing: CameraError.notRunning)
                    return
                }
                guard captureContinuation == nil else {
                    continuation.resume(throwing: CameraError.captureInProgress)
                    return
                }
                captureContinuation = continuation
                photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        // Extract the payload here — AVCapturePhoto is not Sendable, so it must
        // not cross into the session-queue closure.
        let result: Result<Data, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(CameraError.noData)
        }
        sessionQueue.async { [self] in
            guard let continuation = captureContinuation else { return }
            captureContinuation = nil
            continuation.resume(with: result)
        }
    }
}

enum CameraError: LocalizedError {
    case noDevice, cannotAddInput, cannotAddOutput, noData, notRunning, captureInProgress

    var errorDescription: String? {
        switch self {
        case .captureInProgress: return "Çekim zaten sürüyor."
        case .notRunning:        return "Kamera hazır değil, bir saniye bekleyin."
        default:                 return "Fotoğraf çekilemedi, tekrar deneyin."
        }
    }
}

// MARK: - Main camera view

struct CameraView: View {
    @Environment(NavigationModel.self) private var nav

    private let camera = CameraManager.shared

    @State private var showShutterFlash = false
    @State private var authorization: AVAuthorizationStatus = .notDetermined
    @State private var torchOn = false
    @State private var isCapturing = false
    @State private var captureErrorMessage: String?
    @State private var focusPoint: CGPoint?
    @State private var focusRingVisible = false
    @State private var guideVisible = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if authorization == .authorized {
                CameraPreview(manager: camera)
                    .ignoresSafeArea()
                    .onTapGesture(coordinateSpace: .global) { location in
                        focusTapped(at: location)
                    }
            } else if authorization == .denied || authorization == .restricted {
                permissionDeniedView
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
                    colors: [.black.opacity(0.45), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 140)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Plate framing guide
            if authorization == .authorized {
                framingGuide
                    .allowsHitTesting(false)
            }

            // Tap-to-focus ring
            if let focusPoint {
                FocusRing()
                    .position(focusPoint)
                    .opacity(focusRingVisible ? 1 : 0)
                    .allowsHitTesting(false)
            }

            // UI overlay
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomControls
            }

            // Capture error toast
            if let captureErrorMessage {
                VStack {
                    Spacer()
                    Text(captureErrorMessage)
                        .font(.sofraLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Layout.Spacing.lg)
                        .padding(.vertical, Layout.Spacing.md)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.bottom, 180)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
            }
        }
        .task {
            let granted = await camera.requestAccess()
            authorization = granted ? .authorized : camera.authorizationStatus
            if granted {
                camera.startSession()
                withAnimation(.sofraSpring.delay(0.15)) { guideVisible = true }
            }
        }
        .onDisappear {
            torchOn = false
            camera.stopSession()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // Close → daily summary
            Button {
                nav.goToDaily()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            FreeScanBadge()

            Spacer()

            // Torch toggle
            Button {
                torchOn.toggle()
                camera.setTorch(torchOn)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(torchOn ? Color.accentFill : .white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .opacity(authorization == .authorized ? 1 : 0)
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.sm)
    }

    // MARK: - Framing guide

    /// Four corner brackets + hint — frames where the plate should sit.
    private var framingGuide: some View {
        VStack(spacing: Layout.Spacing.lg) {
            CornerBrackets()
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 280, height: 280)

            Text("Tabağı çerçeveye al")
                .font(.sofraLabel)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, Layout.Spacing.md)
                .padding(.vertical, Layout.Spacing.xs)
                .background(.black.opacity(0.35), in: Capsule())
        }
        .opacity(guideVisible ? 1 : 0)
        .scaleEffect(guideVisible ? 1 : 0.92)
        .offset(y: -20)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: Layout.Spacing.lg) {
            // Capture button — copper accent ring around the classic white disc
            Button {
                Task { await capture() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.accentFill.opacity(0.9), lineWidth: 3)
                        .frame(width: 84, height: 84)
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 74, height: 74)
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                        .scaleEffect(isCapturing ? 0.85 : 1)
                }
            }
            .disabled(isCapturing || authorization != .authorized)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isCapturing)

            // Text log alternative
            Button {
                nav.goToTextLog(from: .camera)
            } label: {
                HStack(spacing: Layout.Spacing.xs) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 15))
                    Text("Yazarak ekle")
                        .font(.sofraLabel)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.vertical, Layout.Spacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.bottom, Layout.Spacing.xl)
    }

    // MARK: - Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: Layout.Spacing.lg) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.6))

            Text("Kamera izni gerekli")
                .font(.sofraHeading)
                .foregroundStyle(.white)

            Text("Tabağını tarayabilmek için Ayarlar'dan\nSofra'ya kamera izni ver.")
                .font(.sofraBody)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Ayarlar'ı Aç")
                    .font(.sofraLabel)
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, Layout.Spacing.xl)
                    .padding(.vertical, Layout.Spacing.md)
                    .background(Color.accentFill, in: Capsule())
            }
            .padding(.top, Layout.Spacing.sm)
        }
        .padding(Layout.Spacing.xxl)
    }

    // MARK: - Actions

    private func focusTapped(at location: CGPoint) {
        camera.focus(atLayerPoint: location)
        focusPoint = location
        focusRingVisible = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            focusRingVisible = false
        }
    }

    private func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        // Haptic + shutter flash
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.06)) { showShutterFlash = true }
        try? await Task.sleep(nanoseconds: 60_000_000) // 60ms
        withAnimation(.easeOut(duration: 0.06)) { showShutterFlash = false }

        do {
            let imageData = try await camera.capturePhoto()
            guard let uiImage = UIImage(data: imageData) else {
                throw CameraError.noData
            }
            nav.startAnalysis(imageData: imageData, uiImage: uiImage)
        } catch {
            showCaptureError(error.localizedDescription)
        }
    }

    private func showCaptureError(_ message: String) {
        withAnimation(.sofraSpring) { captureErrorMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.sofraSpring) { captureErrorMessage = nil }
        }
    }
}

// MARK: - Corner brackets shape

/// Four L-shaped corner brackets, like a viewfinder reticle.
struct CornerBrackets: Shape {
    var cornerLength: CGFloat = 34
    var cornerRadius: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = cornerLength
        let r = cornerRadius

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))

        // Top-right
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))

        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))

        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))

        return p
    }
}

// MARK: - Focus ring

struct FocusRing: View {
    @State private var appeared = false

    var body: some View {
        Circle()
            .stroke(Color.accentFill, lineWidth: 2)
            .frame(width: 72, height: 72)
            .scaleEffect(appeared ? 1 : 1.4)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    appeared = true
                }
            }
    }
}

// MARK: - Free scan badge

struct FreeScanBadge: View {
    @State private var counter = FreeScanCounter.shared

    var body: some View {
        if counter.isSubscribed {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: counter.canScanForFree ? "camera.fill" : "lock.fill")
                    .font(.system(size: 11))
                Text(counter.canScanForFree
                     ? "\(counter.remainingFreeScans) ücretsiz tarama"
                     : "Limit doldu")
                    .font(.sofraCaption)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, Layout.Spacing.md)
            .padding(.vertical, Layout.Spacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}
