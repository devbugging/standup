import Foundation
import AVFoundation

enum RecordingError: LocalizedError {
    case permissionDenied
    case failedToStart(String)
    case noAudioCaptured

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access denied. Grant permission in System Settings > Privacy & Security > Microphone."
        case .failedToStart(let msg):
            return "Failed to start recording: \(msg)"
        case .noAudioCaptured:
            return "Recording file is empty — no audio was captured. Check your microphone."
        }
    }
}

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var permissionGranted = false
    @Published var audioLevel: Float = 0
    private var timer: Timer?
    private var levelTimer: Timer?

    var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("standup_recording.m4a")
    }

    override init() {
        super.init()
        checkPermission()
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async { self.permissionGranted = true }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                }
            }
        default:
            DispatchQueue.main.async { self.permissionGranted = false }
        }
    }

    func startRecording() throws {
        // Re-check permission
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            checkPermission()
            throw RecordingError.permissionDenied
        }

        try? FileManager.default.removeItem(at: recordingURL)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        } catch {
            throw RecordingError.failedToStart(error.localizedDescription)
        }

        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()

        let started = audioRecorder?.record() ?? false
        if !started {
            throw RecordingError.failedToStart("AVAudioRecorder.record() returned false")
        }

        isRecording = true
        elapsedTime = 0

        // Elapsed time timer
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.elapsedTime += 1
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Audio level timer for visual feedback
        let lt = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let recorder = self?.audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let level = recorder.averagePower(forChannel: 0)
            // Normalize from dB (-160...0) to 0...1
            let normalized = max(0, min(1, (level + 50) / 50))
            self?.audioLevel = normalized
        }
        RunLoop.main.add(lt, forMode: .common)
        levelTimer = lt
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }

    /// Verify the recording file exists and has content
    func validateRecording() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: recordingURL.path) else {
            throw RecordingError.noAudioCaptured
        }
        guard let attrs = try? fm.attributesOfItem(atPath: recordingURL.path),
              let size = attrs[.size] as? UInt64, size > 1000 else {
            throw RecordingError.noAudioCaptured
        }
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("AudioRecorder: recording finished unsuccessfully")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("AudioRecorder encode error: \(error)")
        }
    }
}
