//
//  TextLogView.swift
//  Calorisor — free-text meal logging alternative.
//
//  User types "2 kepçe mercimek, 1 dilim ekmek" style description.
//  Sent through the same AI proxy (mode: "text") — the backend parses
//  and returns the same VisionResponse shape. The ResultView is reused
//  for the output.
//
//  The draft lives on NavigationModel so backing out of a result (or
//  accidentally closing) never loses typed text. The close button returns
//  to whichever screen opened this one (camera or daily).
//
//  Voice input (SF-EX03): a mic button dictates straight into the same text
//  field via on-device SFSpeechRecognizer (tr-TR / en-US following the app
//  language). Speech only produces text — it never opens a separate nutrition
//  path. The user still reviews the transcript and taps "Analiz Et", so nothing
//  is logged without confirmation on the result screen. If mic/speech
//  permission is denied the field stays fully usable for typing.
//
//  NOTE: MealSpeechRecognizer lives in this file (not its own) so it compiles
//  against the committed .xcodeproj without a `xcodegen generate` step.
//

import SwiftUI
import Speech
import AVFoundation

enum TextLogInputPolicy {
    static let maxCharacters = 300
    static let counterThreshold = 240

    static func limited(_ text: String) -> String {
        String(text.prefix(maxCharacters))
    }
}

struct TextLogView: View {
    @Environment(NavigationModel.self) private var nav

    @State private var textInput: String = ""
    @State private var isScanning = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    /// Live dictation. Its transcript is mirrored into `textInput` so the voice
    /// path and the typed path converge on the exact same analysis.
    @State private var speech = MealSpeechRecognizer()
    /// Text already present when dictation began — the live transcript is
    /// appended onto this so partial-result updates never wipe earlier input.
    @State private var textBeforeDictation = ""

    private let client = AIProxyClient()

    /// One-tap starters — language-aware. Turkish users get Turkey-specific foods;
    /// English users get international foods.
    private var suggestions: [String] {
        let isTurkish: Bool = {
            switch AppLanguage.current {
            case .system:  return Locale.current.identifier.hasPrefix("tr")
            case .turkish: return true
            case .english: return false
            }
        }()
        if isTurkish {
            return [
                "1 çay", "1 simit", "2 kepçe mercimek çorbası", "1 dilim ekmek",
                "1 kase yoğurt", "1 su bardağı ayran", "2 adet yumurta", "1 kase salata",
            ]
        } else {
            return [
                "1 coffee", "1 bread slice", "1 bowl yogurt", "2 eggs",
                "1 bowl salad", "1 apple", "1 banana", "1 glass milk",
            ]
        }
    }

    var body: some View {
        ZStack {
            Color.bgPage.ignoresSafeArea()

            VStack(spacing: Layout.Spacing.lg) {
                header

                // Text input area — inset "pressed" surface per the neomorphic language
                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                    HStack {
                        Text("NE YEDİN?")
                            .font(.sofraEyebrow)
                            .tracking(1.2)
                            .foregroundStyle(Color.textMuted)
                        Spacer()
                        micButton
                    }

                    ZStack(alignment: .topLeading) {
                        if textInput.isEmpty {
                            Text("Örn: 2 kepçe mercimek çorbası, 1 dilim ekmek, 1 kase yoğurt")
                                .font(.sofraBody)
                                .foregroundStyle(Color.textMuted)
                                .padding(.horizontal, Layout.Spacing.md)
                                .padding(.vertical, Layout.Spacing.md)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $textInput)
                            .font(.sofraBody)
                            .foregroundStyle(Color.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(Layout.Spacing.sm)
                            .focused($isFocused)

                        if textInput.count >= TextLogInputPolicy.counterThreshold {
                            Text("\(textInput.count)/\(TextLogInputPolicy.maxCharacters)")
                                .font(.sofraCaption)
                                .foregroundStyle(Color.textMuted)
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .bottomTrailing
                                )
                                .padding(Layout.Spacing.md)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                    .pressedSurface(cornerRadius: Layout.Radius.card)
                }
                .padding(.horizontal, Layout.Spacing.lg)

                voiceStatusBanner

                // Quick suggestion chips
                suggestionChips

                analyzeButton

                Spacer()
            }
        }
        .onAppear {
            textInput = nav.textLogDraft
            // Slight delay so the screen transition lands before the keyboard rises.
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                isFocused = true
            }
        }
        .onChange(of: textInput) { _, newValue in
            let limited = TextLogInputPolicy.limited(newValue)
            if limited != newValue {
                textInput = limited
            }
            nav.textLogDraft = limited
        }
        // Mirror the live transcript into the text field. Rebuilt from the text
        // that was present when dictation started, so partial results only ever
        // grow the dictated tail — earlier typed text is preserved.
        .onChange(of: speech.transcript) { _, transcript in
            let dictated = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dictated.isEmpty else { return }
            let base = textBeforeDictation.trimmingCharacters(in: .whitespacesAndNewlines)
            textInput = base.isEmpty ? dictated : "\(base) \(dictated)"
        }
        // Free the audio session / recognizer if the user leaves mid-dictation.
        .onDisappear { speech.cancel() }
        .alert("Analiz başarısız", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                nav.closeTextLog()
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
            Text("Yazarak Ekle")
                .font(.sofraHeading)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            // Balance the xmark width
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, Layout.Spacing.lg)
        .padding(.top, Layout.Spacing.md)
    }

    // MARK: - Voice input

    /// Round mic toggle. Idle → raised neutral surface; listening → accent fill
    /// with a gentle pulse so the recording state is unmistakable.
    private var micButton: some View {
        Button {
            toggleDictation()
        } label: {
            Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(speech.isListening ? Color.onAccent : Color.textPrimary)
                .frame(width: 38, height: 38)
                .background(
                    speech.isListening ? Color.accentFill : Color.surfaceRaised,
                    in: Circle()
                )
                .raisedSurface(cornerRadius: 19)
                .scaleEffect(speech.isListening ? 1.06 : 1)
                .animation(
                    speech.isListening
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .sofraSpring,
                    value: speech.isListening
                )
        }
        .accessibilityLabel(
            speech.isListening
                ? String(localized: "Dinlemeyi durdur")
                : String(localized: "Sesle ekle")
        )
        .accessibilityHint(String(localized: "Ne yediğini söyle, metne çevrilsin"))
    }

    /// Live-listening indicator + permission/error messaging, shown only when
    /// dictation is active or the recognizer has something to report.
    @ViewBuilder
    private var voiceStatusBanner: some View {
        switch speech.state {
        case .listening:
            HStack(spacing: Layout.Spacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentText)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityHidden(true)
                Text("Dinliyorum… ne yediğini söyle")
                    .font(.sofraCaption)
                    .foregroundStyle(Color.accentText)
                Spacer()
                Button {
                    speech.stop()
                } label: {
                    Text("Durdur")
                        .font(.sofraCaption.weight(.semibold))
                        .foregroundStyle(Color.accentText)
                }
            }
            .padding(.horizontal, Layout.Spacing.md)
            .padding(.vertical, Layout.Spacing.sm)
            .background(Color.accentTintBg, in: Capsule())
            .padding(.horizontal, Layout.Spacing.lg)
            .transition(.opacity)

        case .denied(let reason):
            voiceMessage(
                icon: "mic.slash",
                title: reason == .speech
                    ? String(localized: "Konuşma tanıma izni gerekli")
                    : String(localized: "Mikrofon izni gerekli"),
                detail: String(localized: "Sesle eklemek için Ayarlar'dan izin ver. İstersen yazarak da ekleyebilirsin."),
                showSettings: true
            )

        case .unavailable:
            voiceMessage(
                icon: "mic.slash",
                title: String(localized: "Sesle ekleme kullanılamıyor"),
                detail: String(localized: "Bu dilde ses tanıma hazır değil. Yazarak ekleyebilirsin."),
                showSettings: false
            )

        case .failed:
            voiceMessage(
                icon: "exclamationmark.triangle",
                title: String(localized: "Ses algılanamadı"),
                detail: String(localized: "Tekrar dene ya da yazarak ekle."),
                showSettings: false
            )

        case .idle:
            EmptyView()
        }
    }

    private func voiceMessage(icon: String, title: String, detail: String, showSettings: Bool) -> some View {
        HStack(alignment: .top, spacing: Layout.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sofraCaption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.sofraCaption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showSettings {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Ayarlar'ı Aç")
                            .font(.sofraCaption.weight(.semibold))
                            .foregroundStyle(Color.accentText)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Layout.Spacing.md)
        .background(Color.surfaceFlat, in: RoundedRectangle(cornerRadius: Layout.Radius.control))
        .padding(.horizontal, Layout.Spacing.lg)
        .transition(.opacity)
    }

    /// Start/stop dictation. Starting snapshots the current text so the live
    /// transcript is appended, not overwritten, and dismisses the keyboard so
    /// the mic has a clean audio session.
    private func toggleDictation() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if speech.isListening {
            speech.stop()
        } else {
            isFocused = false
            textBeforeDictation = textInput
            Task { await speech.start() }
        }
    }

    // MARK: - Suggestion chips

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("HIZLI EKLE")
                .font(.sofraEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, Layout.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Spacing.sm) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            appendSuggestion(suggestion)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                    .accessibilityHidden(true)
                                Text(suggestion)
                                    .font(.sofraCaption)
                            }
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, Layout.Spacing.md)
                            .padding(.vertical, Layout.Spacing.sm)
                            .background(Color.surfaceRaised, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.borderHairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Layout.Spacing.lg)
            }
        }
    }

    private func appendSuggestion(_ suggestion: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.sofraSpring) {
            textInput = trimmed.isEmpty ? suggestion : "\(trimmed), \(suggestion)"
        }
    }

    // MARK: - Analyze button

    /// Translucent accentFill over the already-low-contrast bej page nearly
    /// disappeared in the empty state — a flat surfaceFlat/textMuted "neutral
    /// disabled" reads as a real button while still looking inactive, matching
    /// the secondary-button language used elsewhere (e.g. camera's Galeri chip).
    private var isInputEmpty: Bool {
        textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var analyzeButton: some View {
        Button {
            Task { await scan() }
        } label: {
            HStack(spacing: Layout.Spacing.sm) {
                if isScanning {
                    CalorisorIconView(icon: .kepce, size: 18)
                        .modifier(KepceWobbleModifier())
                } else {
                    CalorisorIconView(icon: .kepce, size: 18)
                }
                Text(isScanning ? "Analiz ediliyor..." : "Analiz Et")
                    .font(.sofraLabel)
            }
            .foregroundStyle(isInputEmpty ? Color.textMuted : Color.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Layout.Spacing.md)
            .background(
                isInputEmpty ? Color.surfaceFlat : Color.accentFill,
                in: RoundedRectangle(cornerRadius: Layout.Radius.control)
            )
        }
        .disabled(isInputEmpty || isScanning)
        .padding(.horizontal, Layout.Spacing.lg)
    }

    // MARK: - Scan

    private func scan() async {
        // A running dictation would keep mutating the field mid-request.
        speech.stop()
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isFocused = false
        isScanning = true
        defer { isScanning = false }

        do {
            let result = try await client.scanText(text)
            if !client.isDemoMode {
                FreeScanCounter.shared.recordScan()
            }
            // Reuse the result screen for text-log results
            nav.showResult(
                uiImage: UIImage(),
                items: result.response.items,
                source: .text,
                rawJSON: result.rawJSON
            )
        } catch {
            errorMessage = (error as? AIProxyError)?.localizedDescription
                ?? AIProxyError.scanFailed.localizedDescription
        }
    }
}

// MARK: - Kepçe wobble (replaces the generic SF sparkles pulse)

/// Gentle side-to-side wobble — "Sofra senin için karıştırıyor" metaphor.
private struct KepceWobbleModifier: ViewModifier {
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    angle = 8
                }
            }
    }
}

// MARK: - Meal speech recognizer (SF-EX03)

/// Thin wrapper over `SFSpeechRecognizer` + `AVAudioEngine` for dictating a meal
/// description. It only turns speech into text — the transcript is handed back
/// to `TextLogView`, which runs the *existing* text-analysis flow. There is no
/// separate nutrition path here, and nothing is logged: the recognizer never
/// touches SwiftData or the free-scan counter.
///
/// Locale follows the app language (tr-TR / en-US); recognition is forced
/// on-device when the locale supports it so raw audio never leaves the phone.
@MainActor
@Observable
final class MealSpeechRecognizer {

    enum DeniedReason { case speech, microphone }

    enum State: Equatable {
        case idle
        case listening
        case denied(DeniedReason)
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Best transcript so far (partial results included). `TextLogView` observes
    /// this and mirrors it into the text field.
    private(set) var transcript: String = ""

    var isListening: Bool { state == .listening }

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = MealSpeechRecognizer.preferredLocale) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Locale for recognition, derived from the user's app-language choice so it
    /// matches the language they actually speak/read the app in.
    static var preferredLocale: Locale {
        switch AppLanguage.current {
        case .turkish: return Locale(identifier: "tr-TR")
        case .english: return Locale(identifier: "en-US")
        case .system:
            return Locale.current.identifier.hasPrefix("tr")
                ? Locale(identifier: "tr-TR")
                : Locale(identifier: "en-US")
        }
    }

    // MARK: Start / stop

    func start() async {
        guard let recognizer, recognizer.isAvailable else {
            withAnimation(.sofraSpring) { state = .unavailable }
            return
        }
        guard await requestSpeechAuthorization() else {
            withAnimation(.sofraSpring) { state = .denied(.speech) }
            return
        }
        guard await requestMicrophoneAuthorization() else {
            withAnimation(.sofraSpring) { state = .denied(.microphone) }
            return
        }

        transcript = ""
        do {
            try beginRecognition(with: recognizer)
            withAnimation(.sofraSpring) { state = .listening }
        } catch {
            teardownAudio()
            withAnimation(.sofraSpring) { state = .failed(error.localizedDescription) }
        }
    }

    /// Stop listening but keep whatever was transcribed (the field already holds
    /// it). Safe to call when not listening.
    func stop() {
        guard isListening else { return }
        teardownAudio()
        task?.finish()
        task = nil
        request = nil
        withAnimation(.sofraSpring) { state = .idle }
    }

    /// Abandon the session entirely — used when leaving the screen.
    func cancel() {
        teardownAudio()
        task?.cancel()
        task = nil
        request = nil
        state = .idle
    }

    // MARK: Recognition pipeline

    private func beginRecognition(with recognizer: SFSpeechRecognizer) throws {
        task?.cancel()
        task = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep audio on-device when the locale/model allows it.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Capture the request locally so the audio-thread tap never touches
        // main-actor state.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { @MainActor in self.handleResult(text: text, isFinal: isFinal) }
            }
            if error != nil {
                Task { @MainActor in self.handleRecognitionError() }
            }
        }
    }

    private func handleResult(text: String, isFinal: Bool) {
        transcript = text
        if isFinal { stop() }
    }

    private func handleRecognitionError() {
        // A mid-stream error after we already have text is treated as a normal
        // stop (the transcript stays); an error with nothing captured surfaces.
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            teardownAudio()
            task = nil
            request = nil
            withAnimation(.sofraSpring) { state = .failed("") }
        } else {
            stop()
        }
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Permissions

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default: return false
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        default: return false
        }
    }
}
