import AVFoundation

/// Records the microphone into memory only. Audio is converted to 16 kHz mono
/// 16-bit PCM as it arrives and kept in an array; `stop()` wraps it in a WAV
/// header in memory. Nothing is ever written to disk.
final class Recorder {
    struct Recording {
        let wav: Data
        let duration: TimeInterval
        /// Loudest moment (RMS, 0...1). Near zero means silence, which Whisper
        /// tends to "transcribe" as made-up text, so the caller skips it.
        let peakLevel: Float
    }

    enum RecorderError: LocalizedError {
        case noMicrophone, permissionDenied
        var errorDescription: String? {
            switch self {
            case .noMicrophone: return "No microphone input found."
            case .permissionDenied:
                return "Microphone access is off. Turn on RefineBar in System Settings → Privacy & Security → Microphone."
            }
        }
    }

    static let sampleRate: Double = 16_000

    /// Called on the main thread with the current input level (0...1).
    var onLevel: ((Float) -> Void)?

    /// Created for each recording and released in `stop()`. A long-lived engine
    /// keeps its input unit configured after `stop()`, which leaves Bluetooth
    /// headphones stuck in low-quality headset (HFP) mode until the app quits.
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var peak: Float = 0
    private var converter: AVAudioConverter?
    private(set) var isRecording = false

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start() throws {
        guard !isRecording else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate,
                                            channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else {
            engine.reset()
            throw RecorderError.noMicrophone
        }

        self.converter = converter
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.sampleRate) * 30)
        peak = 0
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer, to: outFormat)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.reset()
            self.converter = nil
            throw error
        }
        self.engine = engine
        isRecording = true
    }

    /// Stops and returns the recording as an in-memory WAV, then frees the samples.
    func stop() -> Recording {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            engine.reset()
            self.engine = nil  // releasing the engine frees the mic, so headphones return to A2DP
        }
        isRecording = false
        converter = nil
        lock.lock()
        let captured = samples
        let loudest = peak
        samples = []
        lock.unlock()
        return Recording(wav: Self.wav(from: captured),
                         duration: Double(captured.count) / Self.sampleRate,
                         peakLevel: loudest)
    }

    private func process(_ buffer: AVAudioPCMBuffer, to outFormat: AVAudioFormat) {
        let level = Self.rms(buffer)

        guard let converter else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, let channel = out.int16ChannelData?[0], out.frameLength > 0 {
            lock.lock()
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
            peak = max(peak, level)
            lock.unlock()
        }

        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(count)))
    }

    /// A standard 44-byte RIFF header followed by the PCM samples.
    static func wav(from samples: [Int16]) -> Data {
        let dataSize = UInt32(samples.count * 2)
        let rate = UInt32(sampleRate)
        var data = Data(capacity: 44 + Int(dataSize))
        func put(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        put("RIFF"); put32(36 + dataSize); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1)  // PCM, mono
        put32(rate); put32(rate * 2); put16(2); put16(16)  // byte rate, block align, bits
        put("data"); put32(dataSize)
        samples.withUnsafeBytes { raw in
            // Int16 is little-endian on Apple silicon and Intel Macs.
            data.append(contentsOf: raw)
        }
        return data
    }
}
