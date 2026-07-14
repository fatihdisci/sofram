//
//  CameraView.swift
//  Calorisor — camera capture screen using AVFoundation.
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
//  Presentation: the camera preview is framed as a flat bordered card centered in
//  the app's own Calorisor chrome (flat page, bordered controls) rather than a
//  full-bleed black takeover — the header, capture button and secondary actions
//  all read as Calorisor UI, with only the live feed itself inside the card.
//

import SwiftUI
import AVFoundation
import UIKit
import PhotosUI

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
    private let sessionQueue = DispatchQueue(label: "com.fatih.calorisor.camera.session")

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
    /// Tap-to-focus point, in the camera card's own local coordinate space
    /// (matches the preview layer's bounds exactly — see `focusTapped`).
    @State private var focusPoint: CGPoint?
    @State private var focusRingVisible = false
    @State private var guideVisible = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: Layout.Spacing.md)

                cameraCard
                    .padding(.horizontal, Layout.Spacing.lg)

                if let captureErrorMessage {
                    Text(captureErrorMessage)
                        .font(.sofraLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Layout.Spacing.lg)
                        .padding(.vertical, Layout.Spacing.sm)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(.top, Layout.Spacing.md)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: Layout.Spacing.md)

                bottomControls
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
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                defer { selectedPhotoItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    showCaptureError("Fotoğraf yüklenemedi.")
                    return
                }
                nav.startAnalysis(imageData: data, uiImage: uiImage)
            }
        }
        .onDisappear {
            torchOn = false
            camera.stopSession()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: Layout.Spacing.xs) {
            HStack {
                Button {
                    nav.goToDaily()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(Color.surfaceRaised, in: Circle())
                        .raisedSurface(cornerRadius: 21)
                        .accessibilityLabel(String(localized: "Kapat"))
                }

                Spacer()

                Text("Tabağını Tara")
                    .font(.sofraHeading)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Button {
                    torchOn.toggle()
                    camera.setTorch(torchOn)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(torchOn ? Color.accentFill : Color.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(Color.surfaceRaised, in: Circle())
                        .raisedSurface(cornerRadius: 21)
                        .accessibilityLabel(torchOn ? String(localized: "Flası kapat") : String(localized: "Flası aç"))
                }
                .opacity(authorization == .authorized ? 1 : 0.35)
                .disabled(authorization != .authorized)
            }

            FreeScanBadge()
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.sm)
    }

    // MARK: - Camera card

    /// The live feed, framed as a raised card in the app's own palette — the
    /// only full-bleed content is the video itself, clipped to the card shape.
    private var cameraCard: some View {
        ZStack {
            cardContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showShutterFlash {
                Color.white
                    .transition(.opacity)
            }

            if authorization == .authorized {
                framingGuide
            }

            if let focusPoint {
                FocusRing()
                    .position(focusPoint)
                    .opacity(focusRingVisible ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.raisedContainer, style: .continuous))
        .raisedSurface(cornerRadius: Layout.Radius.raisedContainer)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var cardContent: some View {
        if authorization == .authorized {
            CameraPreview(manager: camera)
                .onTapGesture(coordinateSpace: .local) { location in
                    focusTapped(at: location)
                }
        } else if authorization == .denied || authorization == .restricted {
            permissionDeniedView
        } else {
            cardPlaceholder
        }
    }

    private var cardPlaceholder: some View {
        CalorisorIconView(icon: .tabak, size: 40)
            .foregroundStyle(Color.textMuted.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Framing guide

    /// Corner brackets + hint, overlaid on the live feed inside the card.
    private var framingGuide: some View {
        ZStack {
            CornerBrackets()
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .padding(28)

            VStack {
                Spacer()
                Text("Tabağı çerçeveye al")
                    .font(.sofraLabel)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, Layout.Spacing.md)
                    .padding(.vertical, Layout.Spacing.xs)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, Layout.Spacing.lg)
            }
        }
        .opacity(guideVisible ? 1 : 0)
        .scaleEffect(guideVisible ? 1 : 0.92)
        .allowsHitTesting(false)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: Layout.Spacing.lg) {
            // Capture button — raised app-style circle, not a generic shutter ring.
            Button {
                Task { await capture() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.surfaceRaised)
                        .frame(width: 92, height: 92)
                        .raisedSurface(cornerRadius: 46)
                    Circle()
                        .fill(Color.accentFill)
                        .frame(width: 74, height: 74)
                    CalorisorIconView(icon: .capture, size: 30)
                        .foregroundStyle(Color.onAccent)
                }
                .accessibilityLabel(String(localized: "Fotoğraf çek"))
                .scaleEffect(isCapturing ? 0.88 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isCapturing || authorization != .authorized)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isCapturing)

            HStack(spacing: Layout.Spacing.md) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: Layout.Spacing.xs) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 14))
                        Text("Galeri")
                            .font(.sofraLabel)
                    }
                    .accessibilityLabel(String(localized: "Galeri"))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.vertical, Layout.Spacing.sm)
                    .background(Color.surfaceFlat, in: Capsule())
                }

                Button {
                    nav.goToTextLog(from: .camera)
                } label: {
                    HStack(spacing: Layout.Spacing.xs) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 14))
                        Text("Yazarak ekle")
                            .font(.sofraLabel)
                    }
                    .accessibilityLabel(String(localized: "Yazarak ekle"))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.vertical, Layout.Spacing.sm)
                    .background(Color.surfaceFlat, in: Capsule())
                }
            }
        }
        .padding(.bottom, Layout.Spacing.lg)
    }

    // MARK: - Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: Layout.Spacing.md) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)

            Text("Kamera izni gerekli")
                .font(.sofraLabel)
                .foregroundStyle(Color.textPrimary)

            Text("Tabağını tarayabilmek için\nAyarlar'dan izin ver.")
                .font(.sofraCaption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Ayarlar'ı Aç")
                    .font(.sofraLabel)
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, Layout.Spacing.lg)
                    .padding(.vertical, Layout.Spacing.sm)
                    .background(Color.accentFill, in: Capsule())
            }
            .padding(.top, Layout.Spacing.xs)
        }
        .padding(Layout.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// `location` is in the camera card's local coordinate space, which is
    /// exactly the preview layer's own bounds (PreviewView keeps
    /// `previewLayer.frame = bounds` in `layoutSubviews`) — no conversion needed.
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

/// Four L-shaped corner brackets, like a viewfinder reticle. Also used by
/// AnalysisOverlay's scanning treatment.
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
                Image(systemName: counter.canScan(for: .photo) ? "camera.fill" : "lock.fill")
                    .font(.system(size: 10))
                Text(counter.canScan(for: .photo)
                     ? String(localized: "\(counter.remainingPhotoScans) ücretsiz fotoğraf")
                     : String(localized: "Limit doldu"))
                    .font(.sofraCaption)
            }
            .foregroundStyle(Color.accentText)
            .padding(.horizontal, Layout.Spacing.sm)
            .padding(.vertical, 3)
            .background(Color.accentTintBg, in: Capsule())
        }
    }
}
