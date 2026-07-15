import Combine
import Foundation

#if canImport(Speech)
@preconcurrency import Speech
#endif

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

enum BrowserVoiceAuthorizationStatus: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

enum BrowserVoiceInputState: Equatable, Sendable {
    case unavailable(reason: String)
    case denied(reason: String)
    case recording
    case transcribing
    case stopped
    case failed(message: String)

    var isCapturingAudio: Bool {
        switch self {
        case .recording, .transcribing:
            true
        case .unavailable, .denied, .stopped, .failed:
            false
        }
    }
}

struct BrowserVoiceRecognitionConfiguration: Equatable, Sendable {
    var localeIdentifier: String?
    var requiresOnDeviceRecognition: Bool

    init(
        localeIdentifier: String? = nil,
        requiresOnDeviceRecognition: Bool = true
    ) {
        let trimmedLocale = localeIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.localeIdentifier = trimmedLocale?.isEmpty == false ? trimmedLocale : nil
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
    }
}

struct BrowserVoiceInputCapability: Equatable, Sendable {
    var isAvailable: Bool
    var reason: String

    static let unsupported = BrowserVoiceInputCapability(
        isAvailable: false,
        reason: "Speech recognition and audio input are unavailable on this platform."
    )
}

struct BrowserVoiceRecognitionUpdate: Equatable, Sendable {
    var transcript: String
    var isFinal: Bool
}

enum BrowserVoiceInputError: Error, Equatable, LocalizedError, Sendable {
    case unavailable(String)
    case authorizationDenied(String)
    case onDeviceRecognitionUnavailable
    case audioInputUnavailable
    case alreadyRunning
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .authorizationDenied(let message), .recognitionFailed(let message):
            message
        case .onDeviceRecognitionUnavailable:
            "On-device speech recognition is unavailable for the selected language."
        case .audioInputUnavailable:
            "No usable microphone input is available."
        case .alreadyRunning:
            "Voice input is already running."
        }
    }
}

typealias BrowserVoiceRecognitionHandler = @MainActor (
    Result<BrowserVoiceRecognitionUpdate, BrowserVoiceInputError>
) -> Void

/// Injectable boundary around speech authorization and audio capture. Fakes can
/// drive updates synchronously without touching Speech, AVFoundation, or a real
/// microphone.
@MainActor
protocol BrowserVoiceInputServicing: AnyObject {
    var authorizationStatus: BrowserVoiceAuthorizationStatus { get }

    func capability(
        for configuration: BrowserVoiceRecognitionConfiguration
    ) -> BrowserVoiceInputCapability

    func requestAuthorization() async -> BrowserVoiceAuthorizationStatus

    func startRecognition(
        configuration: BrowserVoiceRecognitionConfiguration,
        onUpdate: @escaping BrowserVoiceRecognitionHandler
    ) throws

    func stopRecognition()
    func cancelRecognition()
}

/// Owns an editable voice draft. It intentionally has no send/submit callback:
/// recognized text remains a bounded draft until the user edits or submits it
/// through a separate UI action.
@MainActor
final class BrowserVoiceInputController: ObservableObject {
    static let defaultMaximumTranscriptCharacters = 12_000

    @Published private(set) var state: BrowserVoiceInputState
    @Published private(set) var transcript: String
    @Published private(set) var authorizationStatus: BrowserVoiceAuthorizationStatus

    let configuration: BrowserVoiceRecognitionConfiguration
    let maximumTranscriptCharacters: Int

    private let service: any BrowserVoiceInputServicing
    private var activeAttemptID: UUID?
    private var activeSessionID: UUID?
    private var transcriptPrefix = ""

    init(
        service: (any BrowserVoiceInputServicing)? = nil,
        configuration: BrowserVoiceRecognitionConfiguration = BrowserVoiceRecognitionConfiguration(),
        maximumTranscriptCharacters: Int = BrowserVoiceInputController.defaultMaximumTranscriptCharacters,
        transcript: String = ""
    ) {
        let resolvedService = service ?? BrowserVoiceInputServiceFactory.makeDefault()
        let boundedMaximum = min(max(maximumTranscriptCharacters, 256), 50_000)
        let capability = resolvedService.capability(for: configuration)
        let authorizationStatus = resolvedService.authorizationStatus

        self.service = resolvedService
        self.configuration = configuration
        self.maximumTranscriptCharacters = boundedMaximum
        self.transcript = Self.boundedTranscript(transcript, limit: boundedMaximum)
        self.authorizationStatus = authorizationStatus

        if !capability.isAvailable {
            self.state = .unavailable(reason: capability.reason)
        } else {
            switch authorizationStatus {
            case .denied, .restricted:
                self.state = .denied(reason: Self.deniedMessage(for: authorizationStatus))
            case .notDetermined, .authorized:
                self.state = .stopped
            case .unavailable:
                self.state = .unavailable(reason: capability.reason)
            }
        }
    }

    var canStartFromUserAction: Bool {
        guard activeAttemptID == nil, activeSessionID == nil else { return false }
        return service.capability(for: configuration).isAvailable
            && authorizationStatus != .denied
            && authorizationStatus != .restricted
            && authorizationStatus != .unavailable
    }

    /// Re-evaluates capability and permission state without ever prompting.
    func refreshAvailability() {
        guard activeAttemptID == nil, activeSessionID == nil else { return }
        let capability = service.capability(for: configuration)
        authorizationStatus = service.authorizationStatus
        guard capability.isAvailable else {
            state = .unavailable(reason: capability.reason)
            return
        }
        switch authorizationStatus {
        case .denied, .restricted:
            state = .denied(reason: Self.deniedMessage(for: authorizationStatus))
        case .unavailable:
            state = .unavailable(reason: capability.reason)
        case .notDetermined, .authorized:
            state = .stopped
        }
    }

    /// The only controller entry point that may request Speech and microphone
    /// authorization. Call it directly from an explicit user gesture.
    func startFromUserAction(replacingTranscript: Bool = false) async {
        guard activeAttemptID == nil, activeSessionID == nil else { return }

        let capability = service.capability(for: configuration)
        guard capability.isAvailable else {
            state = .unavailable(reason: capability.reason)
            return
        }

        let attemptID = UUID()
        activeAttemptID = attemptID
        var status = service.authorizationStatus
        if status == .notDetermined {
            status = await service.requestAuthorization()
        }

        guard activeAttemptID == attemptID else { return }
        activeAttemptID = nil
        authorizationStatus = status

        switch status {
        case .authorized:
            break
        case .denied, .restricted:
            state = .denied(reason: Self.deniedMessage(for: status))
            return
        case .notDetermined:
            state = .denied(reason: "Speech and microphone access were not granted.")
            return
        case .unavailable:
            state = .unavailable(reason: capability.reason)
            return
        }

        transcriptPrefix = replacingTranscript ? "" : transcript
        if replacingTranscript {
            transcript = ""
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        state = .recording
        do {
            try service.startRecognition(configuration: configuration) { [weak self] result in
                self?.apply(result, sessionID: sessionID)
            }
        } catch let error as BrowserVoiceInputError {
            failStart(error, sessionID: sessionID)
        } catch {
            failStart(.recognitionFailed(error.localizedDescription), sessionID: sessionID)
        }
    }

    /// Ends microphone capture and allows the recognizer to finish its final
    /// transcription. `cancel()` remains available for immediate teardown.
    func stopFromUserAction() {
        if activeAttemptID != nil, activeSessionID == nil {
            cancel()
            return
        }
        guard activeSessionID != nil else { return }
        service.stopRecognition()
        state = .transcribing
    }

    /// Immediately invalidates callbacks and releases speech/audio resources.
    func cancel() {
        activeAttemptID = nil
        activeSessionID = nil
        transcriptPrefix = ""
        service.cancelRecognition()
        refreshAvailability()
    }

    /// Replaces the draft with a bounded user edit. Editing during capture first
    /// cancels capture so a late partial result cannot overwrite the user's text.
    func editTranscript(_ text: String) {
        if activeAttemptID != nil || activeSessionID != nil {
            cancel()
        }
        transcript = Self.boundedTranscript(text, limit: maximumTranscriptCharacters)
    }

    func clearTranscript() {
        editTranscript("")
    }

    private func apply(
        _ result: Result<BrowserVoiceRecognitionUpdate, BrowserVoiceInputError>,
        sessionID: UUID
    ) {
        guard activeSessionID == sessionID else { return }
        switch result {
        case .success(let update):
            transcript = Self.merging(
                prefix: transcriptPrefix,
                recognition: update.transcript,
                limit: maximumTranscriptCharacters
            )
            if update.isFinal {
                activeSessionID = nil
                transcriptPrefix = ""
                state = .stopped
            } else {
                state = .transcribing
            }
        case .failure(let error):
            activeSessionID = nil
            transcriptPrefix = ""
            transition(for: error)
        }
    }

    private func failStart(_ error: BrowserVoiceInputError, sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
        transcriptPrefix = ""
        service.cancelRecognition()
        transition(for: error)
    }

    private func transition(for error: BrowserVoiceInputError) {
        switch error {
        case .authorizationDenied(let message):
            authorizationStatus = .denied
            state = .denied(reason: message)
        case .unavailable, .onDeviceRecognitionUnavailable, .audioInputUnavailable:
            state = .unavailable(reason: error.localizedDescription)
        case .alreadyRunning, .recognitionFailed:
            state = .failed(message: error.localizedDescription)
        }
    }

    private static func deniedMessage(for status: BrowserVoiceAuthorizationStatus) -> String {
        switch status {
        case .restricted:
            "Speech or microphone access is restricted on this device."
        case .denied:
            "Speech and microphone access are required for voice input."
        case .notDetermined, .authorized, .unavailable:
            "Speech and microphone access were not granted."
        }
    }

    private static func merging(prefix: String, recognition: String, limit: Int) -> String {
        let boundedPrefix = boundedTranscript(prefix, limit: limit)
        let remaining = max(0, limit - boundedPrefix.count)
        guard remaining > 0 else { return boundedPrefix }
        let boundedRecognition = boundedTranscript(recognition, limit: remaining)
        guard !boundedPrefix.isEmpty, !boundedRecognition.isEmpty else {
            return boundedPrefix.isEmpty ? boundedRecognition : boundedPrefix
        }
        let separator = boundedPrefix.last?.isWhitespace == true ? "" : " "
        return boundedTranscript(boundedPrefix + separator + boundedRecognition, limit: limit)
    }

    private static func boundedTranscript(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}

@MainActor
enum BrowserVoiceInputServiceFactory {
    static func makeDefault() -> any BrowserVoiceInputServicing {
#if canImport(Speech) && canImport(AVFoundation)
        SystemBrowserVoiceInputService()
#else
        UnavailableBrowserVoiceInputService()
#endif
    }
}

@MainActor
final class UnavailableBrowserVoiceInputService: BrowserVoiceInputServicing {
    var authorizationStatus: BrowserVoiceAuthorizationStatus { .unavailable }

    func capability(
        for configuration: BrowserVoiceRecognitionConfiguration
    ) -> BrowserVoiceInputCapability {
        .unsupported
    }

    func requestAuthorization() async -> BrowserVoiceAuthorizationStatus {
        .unavailable
    }

    func startRecognition(
        configuration: BrowserVoiceRecognitionConfiguration,
        onUpdate: @escaping BrowserVoiceRecognitionHandler
    ) throws {
        throw BrowserVoiceInputError.unavailable(BrowserVoiceInputCapability.unsupported.reason)
    }

    func stopRecognition() {}
    func cancelRecognition() {}
}

#if canImport(Speech) && canImport(AVFoundation)
@MainActor
final class SystemBrowserVoiceInputService: BrowserVoiceInputServicing {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var updateHandler: BrowserVoiceRecognitionHandler?
    private var hasInstalledInputTap = false
#if os(iOS) || os(visionOS)
    private var hasActiveAudioSession = false
#endif

    var authorizationStatus: BrowserVoiceAuthorizationStatus {
        Self.combinedAuthorizationStatus(
            speech: Self.speechAuthorizationStatus,
            microphone: Self.microphoneAuthorizationStatus
        )
    }

    func capability(
        for configuration: BrowserVoiceRecognitionConfiguration
    ) -> BrowserVoiceInputCapability {
        guard let recognizer = speechRecognizer(for: configuration) else {
            return BrowserVoiceInputCapability(
                isAvailable: false,
                reason: "Speech recognition is unavailable for the selected language."
            )
        }
        guard recognizer.isAvailable else {
            return BrowserVoiceInputCapability(
                isAvailable: false,
                reason: "Speech recognition is temporarily unavailable."
            )
        }
        if configuration.requiresOnDeviceRecognition, !recognizer.supportsOnDeviceRecognition {
            return BrowserVoiceInputCapability(
                isAvailable: false,
                reason: BrowserVoiceInputError.onDeviceRecognitionUnavailable.localizedDescription
            )
        }
        return BrowserVoiceInputCapability(isAvailable: true, reason: "Voice input is available.")
    }

    func requestAuthorization() async -> BrowserVoiceAuthorizationStatus {
        if Self.speechAuthorizationStatus == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: Self.mapSpeechAuthorization(status))
                }
            }
        }
        if Self.microphoneAuthorizationStatus == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return authorizationStatus
    }

    func startRecognition(
        configuration: BrowserVoiceRecognitionConfiguration,
        onUpdate: @escaping BrowserVoiceRecognitionHandler
    ) throws {
        guard recognitionTask == nil, audioEngine == nil else {
            throw BrowserVoiceInputError.alreadyRunning
        }
        guard authorizationStatus == .authorized else {
            throw BrowserVoiceInputError.authorizationDenied(
                "Speech and microphone access are required for voice input."
            )
        }
        let capability = capability(for: configuration)
        guard capability.isAvailable else {
            if configuration.requiresOnDeviceRecognition {
                throw BrowserVoiceInputError.onDeviceRecognitionUnavailable
            }
            throw BrowserVoiceInputError.unavailable(capability.reason)
        }
        guard let recognizer = speechRecognizer(for: configuration) else {
            throw BrowserVoiceInputError.unavailable(capability.reason)
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = configuration.requiresOnDeviceRecognition
        request.taskHint = .dictation
        request.addsPunctuation = true

        do {
            try activateAudioSessionIfNeeded()
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
                throw BrowserVoiceInputError.audioInputUnavailable
            }

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: recordingFormat
            ) { buffer, _ in
                request.append(buffer)
            }
            hasInstalledInputTap = true
            audioEngine = engine
            recognitionRequest = request
            updateHandler = onUpdate
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let errorMessage = error?.localizedDescription
                Task { @MainActor [weak self] in
                    self?.receiveRecognitionCallback(
                        transcript: transcript,
                        isFinal: isFinal,
                        errorMessage: errorMessage
                    )
                }
            }
            engine.prepare()
            try engine.start()
        } catch let error as BrowserVoiceInputError {
            cancelRecognition()
            throw error
        } catch {
            cancelRecognition()
            throw BrowserVoiceInputError.recognitionFailed(error.localizedDescription)
        }
    }

    func stopRecognition() {
        guard recognitionTask != nil else { return }
        stopAudioCapture()
        recognitionRequest?.endAudio()
    }

    func cancelRecognition() {
        updateHandler = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        stopAudioCapture()
        audioEngine = nil
    }

    private func receiveRecognitionCallback(
        transcript: String?,
        isFinal: Bool,
        errorMessage: String?
    ) {
        guard let updateHandler else { return }
        if let transcript {
            updateHandler(.success(BrowserVoiceRecognitionUpdate(transcript: transcript, isFinal: isFinal)))
            if isFinal {
                finishRecognition()
            }
            return
        }
        if let errorMessage {
            self.updateHandler = nil
            finishRecognition()
            updateHandler(.failure(.recognitionFailed(errorMessage)))
        }
    }

    private func finishRecognition() {
        recognitionTask = nil
        recognitionRequest = nil
        stopAudioCapture()
        audioEngine = nil
        updateHandler = nil
    }

    private func stopAudioCapture() {
        audioEngine?.stop()
        if hasInstalledInputTap {
            audioEngine?.inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }
        deactivateAudioSessionIfNeeded()
    }

    private func speechRecognizer(
        for configuration: BrowserVoiceRecognitionConfiguration
    ) -> SFSpeechRecognizer? {
        let locale = configuration.localeIdentifier.map(Locale.init(identifier:)) ?? .current
        return SFSpeechRecognizer(locale: locale)
    }

    private static var speechAuthorizationStatus: BrowserVoiceAuthorizationStatus {
        mapSpeechAuthorization(SFSpeechRecognizer.authorizationStatus())
    }

    private static var microphoneAuthorizationStatus: BrowserVoiceAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }

    private static func mapSpeechAuthorization(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> BrowserVoiceAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }

    private static func combinedAuthorizationStatus(
        speech: BrowserVoiceAuthorizationStatus,
        microphone: BrowserVoiceAuthorizationStatus
    ) -> BrowserVoiceAuthorizationStatus {
        let statuses = [speech, microphone]
        if statuses.contains(.denied) { return .denied }
        if statuses.contains(.restricted) { return .restricted }
        if statuses.contains(.unavailable) { return .unavailable }
        if statuses.contains(.notDetermined) { return .notDetermined }
        return .authorized
    }

    private func activateAudioSessionIfNeeded() throws {
#if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)
        hasActiveAudioSession = true
#endif
    }

    private func deactivateAudioSessionIfNeeded() {
#if os(iOS) || os(visionOS)
        guard hasActiveAudioSession else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
        hasActiveAudioSession = false
#endif
    }
}
#endif
