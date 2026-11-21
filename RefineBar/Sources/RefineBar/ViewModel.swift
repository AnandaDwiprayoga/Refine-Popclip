import RefineCore
import AppKit
import Combine

/// The panel's state: draft text, recording, the idle timer and the latest result.
@MainActor
final class ViewModel: ObservableObject {
    struct Style: Identifiable, Hashable {
        let id: String
        let label: String
    }

    static let styles = [
        Style(id: "spoken", label: "Spoken"),
        Style(id: "me", label: "My style"),
        Style(id: "polite", label: "Polite"),
        Style(id: "short", label: "Short"),
    ]

    /// How long you pause typing before the draft is refined.
    static let idleDelay: Duration = .milliseconds(1500)
    static let maxRecording: TimeInterval = 120
    /// Below this RMS level the recording is treated as silence.
    static let silenceLevel: Float = 0.008

    @Published var draft = "" {
        didSet { if draft != oldValue && !settingDraftProgrammatically { draftEdited() } }
    }
    @Published var style: String {
        didSet {
            guard style != oldValue else { return }
            UserDefaults.standard.set(style, forKey: "style")
            refineNow()
        }
    }
    @Published private(set) var result = ""
    @Published private(set) var status = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var showSettings = false
    @Published private(set) var copied = false

    @Published var hiddenTerms: String {
        didSet { UserDefaults.standard.set(hiddenTerms, forKey: "hiddenTerms") }
    }
    @Published private(set) var hasAPIKey = Keychain.apiKey() != nil

    /// Lets the menu bar icon show when recording is on.
    var onRecordingChange: ((Bool) -> Void)?

    private let refiner: Refiner?
    private let loadError: String?
    private let recorder = Recorder()
    private var settingDraftProgrammatically = false
    private var idleTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    /// Bumped by every edit or new request. A reply for an older generation is dropped.
    private var generation = 0
    private var lastSent: (text: String, style: String)?

    init() {
        let defaults = UserDefaults.standard
        style = defaults.string(forKey: "style").flatMap { id in Self.styles.first { $0.id == id }?.id } ?? "spoken"
        hiddenTerms = defaults.string(forKey: "hiddenTerms") ?? ""

        do {
            guard let dir = RefineJS.defaultDirectory() else {
                throw GroqError(status: nil, message: "Refine's JS files weren't found. Rebuild with RefineBar/build.sh.")
            }
            refiner = try Refiner(js: RefineJS(directory: dir))
            loadError = nil
        } catch {
            refiner = nil
            loadError = error.localizedDescription
        }
        errorMessage = loadError
        if !hasAPIKey { showSettings = true }

        recorder.onLevel = { [weak self] level in
            guard let self, self.isRecording else { return }
            self.level = level
        }
    }

    // MARK: Typing

    private func draftEdited() {
        // New typing makes any pending or in-flight result stale.
        idleTask?.cancel()
        cancelWork()
        copied = false
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = ""
            return
        }
        status = "Waiting for you to stop typing…"
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled else { return }
            self?.refineNow()
        }
    }

    /// Refines the current draft. Skips it if nothing changed since the last result.
    func refineNow(force: Bool = false, startedAt: Date? = nil) {
        idleTask?.cancel()
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !force, let last = lastSent, last.text == text, last.style == style, errorMessage == nil { return }
        guard let refiner else { errorMessage = loadError; return }
        guard let apiKey = currentAPIKey() else { return }

        cancelWork()
        let generation = self.generation
        let style = self.style
        let terms = hiddenTerms
        let started = startedAt ?? Date()
        isBusy = true
        errorMessage = nil
        status = "Refining…"

        workTask = Task { [weak self] in
            do {
                let output = try await refiner.refine(text, style: style, hiddenTerms: terms, apiKey: apiKey)
                guard let self, self.generation == generation else { return }
                self.isBusy = false
                self.lastSent = (text, style)
                if let output {
                    self.result = output
                    self.status = String(format: "Done in %.1f s", Date().timeIntervalSince(started))
                } else {
                    self.status = "Nothing to refine"
                }
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.isBusy = false
                self.fail(error)
            }
        }
    }

    // MARK: Voice

    func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard refiner != nil else { errorMessage = loadError; return }
        guard currentAPIKey() != nil else { return }
        idleTask?.cancel()
        cancelWork()
        errorMessage = nil
        Task { [weak self] in
            guard await Recorder.requestPermission() else {
                self?.fail(Recorder.RecorderError.permissionDenied)
                return
            }
            self?.beginRecording()
        }
    }

    private func beginRecording() {
        do {
            try recorder.start()
        } catch {
            fail(error)
            return
        }
        isRecording = true
        onRecordingChange?(true)
        elapsed = 0
        level = 0
        status = "Listening… press Stop when you're done"
        let started = Date()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isRecording else { return }
                self.elapsed = Date().timeIntervalSince(started)
                if self.elapsed >= Self.maxRecording { self.stopRecording() }
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        timerTask?.cancel()
        let recording = recorder.stop()
        isRecording = false
        onRecordingChange?(false)
        level = 0

        guard recording.duration >= 0.4 else {
            status = "Too short. Hold on a bit longer next time."
            return
        }
        guard recording.peakLevel >= Self.silenceLevel else {
            status = "Didn't hear anything. Check your microphone."
            return
        }
        guard let apiKey = currentAPIKey() else { return }

        cancelWork()
        let generation = self.generation
        let stoppedAt = Date()
        isBusy = true
        status = "Transcribing…"
        workTask = Task { [weak self] in
            do {
                let transcript = try await Groq.transcribe(wav: recording.wav, apiKey: apiKey)
                guard let self, self.generation == generation else { return }
                self.isBusy = false
                guard !transcript.isEmpty else {
                    self.status = "Didn't catch that. Try again."
                    return
                }
                // The transcript lands in the text box, so a misheard word can be fixed
                // there and the idle timer refines it again.
                self.settingDraftProgrammatically = true
                self.draft = transcript
                self.settingDraftProgrammatically = false
                self.refineNow(force: true, startedAt: stoppedAt)
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.isBusy = false
                self.fail(error)
            }
        }
    }

    // MARK: Actions

    func copyResult() {
        guard !result.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        copied = true
    }

    func clear() {
        settingDraftProgrammatically = true
        draft = ""
        settingDraftProgrammatically = false
        idleTask?.cancel()
        cancelWork()
        result = ""
        status = ""
        errorMessage = loadError
        lastSent = nil
        copied = false
    }

    func saveAPIKey(_ key: String) -> Bool {
        let ok = Keychain.setAPIKey(key)
        hasAPIKey = Keychain.apiKey() != nil
        if ok && hasAPIKey {
            errorMessage = loadError
            showSettings = false
        }
        return ok
    }

    // MARK: Helpers

    private func currentAPIKey() -> String? {
        if let key = Keychain.apiKey() { return key }
        hasAPIKey = false
        errorMessage = "Add your Groq API key first."
        showSettings = true
        return nil
    }

    private func cancelWork() {
        generation += 1
        workTask?.cancel()
        workTask = nil
        isBusy = false
    }

    private func fail(_ error: Error) {
        status = ""
        errorMessage = error.localizedDescription
        if let groq = error as? GroqError, groq.status == 401 { showSettings = true }
    }
}
