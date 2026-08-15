import AVFoundation
import Foundation

/// Direct native input-to-output audio tap, per docs/audio-architecture.md:
/// AVAudioEngine's input node connected straight into the output node so
/// passthrough happens inside the native audio graph's real-time render
/// path, not through Dart. Dart only calls start/stop and reads
/// level/route/interruption events via `onEvent`.
///
/// NOTE: this file could not be compiled or run in the sandboxed Linux
/// build environment used to write it (no Xcode/macOS toolchain
/// available here). It follows the AVAudioEngine APIs and
/// AVAudioSession configuration documented in docs/audio-architecture.md
/// and mirrors the structure of the verified Android implementation in
/// AudioEngine.kt, but it is unverified — flagged explicitly in the
/// final report rather than claimed as tested.
///
/// Two fixes were ported over after real-device testing on Android
/// surfaced them there (see AudioEngine.kt's header comment for the
/// full story) — applied here proactively since the same root causes
/// apply to AVAudioSession, but neither has been confirmed on an
/// actual iPhone:
/// - `.voiceChat` mode applies telephony-tuned AGC/echo-cancellation
///   that measurably quietened monitored audio on Android's equivalent
///   preset; switched to `.measurement`, which leaves that processing
///   off. Echo cancellation isn't needed here since monitoring is only
///   ever allowed through headphones, never the open speaker.
/// - Letting the OS pick the input route implicitly was unreliable on
///   Android (it silently kept the phone's own mic even with a
///   Bluetooth headset connected and allowed). Explicitly preferring
///   the Bluetooth HFP input when available, rather than hoping
///   `.allowBluetooth` alone routes it correctly.
final class AudioEngine {
    typealias EventSender = (_ event: [String: Any?]) -> Void

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var isRunning = false
    private var pausedByInterruption = false
    private let onEvent: EventSender

    private var levelBufferCounter = 0
    private let levelEveryNBuffers = 5

    init(onEvent: @escaping EventSender) {
        self.onEvent = onEvent
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func currentRoute() -> String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        var sawBluetooth = false
        var sawWired = false
        for output in outputs {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                sawBluetooth = true
            case .headphones, .headsetMic, .usbAudio:
                sawWired = true
            default:
                break
            }
        }
        if sawBluetooth { return "bluetooth" }
        if sawWired { return "headphones" }
        return "speaker"
    }

    /// Bluetooth headsets that support HFP (the profile carrying a mic
    /// signal) don't always become the active input just because
    /// `.allowBluetooth` is set — the Android equivalent (implicit SCO
    /// routing) turned out not to be reliable either. Ask explicitly
    /// instead of assuming.
    private func preferBluetoothInputIfAvailable(_ session: AVAudioSession) {
        guard let inputs = session.availableInputs else { return }
        guard let bluetoothInput = inputs.first(where: { $0.portType == .bluetoothHFP }) else {
            return
        }
        try? session.setPreferredInput(bluetoothInput)
    }

    enum EngineError: Error {
        case permissionDenied
        case sessionConfigurationFailed(Error)
        case engineStartFailed(Error)
        case fileCreationFailed(Error)
    }

    func start(outputPath: String) throws {
        if isRunning { return }

        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            throw EngineError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            preferBluetoothInputIfAvailable(session)
        } catch {
            throw EngineError.sessionConfigurationFailed(error)
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        if audioFile == nil {
            let url = URL(fileURLWithPath: outputPath)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ]
            do {
                audioFile = try AVAudioFile(forWriting: url, settings: settings)
            } catch {
                throw EngineError.fileCreationFailed(error)
            }
        }

        // Direct tap: input routed straight to output inside the engine's
        // render graph. The install-tap block below only mirrors frames
        // to disk and computes a metering level — it never buffers or
        // delays what the engine already routed to the output.
        engine.connect(input, to: engine.mainMixerNode, format: inputFormat)
        engine.mainMixerNode.outputVolume = 1.0

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
            [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw EngineError.engineStartFailed(error)
        }

        pausedByInterruption = false
        isRunning = true
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        if let file = audioFile {
            try? file.write(from: buffer)
        }

        levelBufferCounter += 1
        if levelBufferCounter % levelEveryNBuffers == 0 {
            let level = Double(peakAmplitude(of: buffer))
            let sender = onEvent
            DispatchQueue.main.async {
                sender(["type": "level", "level": level])
            }
        }
    }

    private func peakAmplitude(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        var peak: Float = 0
        let samples = channelData[0]
        for i in 0..<frameLength {
            let v = abs(samples[i])
            if v > peak { peak = v }
        }
        return min(peak, 1.0)
    }

    func stop() {
        guard isRunning || pausedByInterruption else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRunning = false
        pausedByInterruption = false
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }

    private func pauseForInterruption(reason: String) {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        pausedByInterruption = true
        let sender = onEvent
        DispatchQueue.main.async {
            sender(["type": "interruption", "reason": reason])
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        let route = currentRoute()
        let sender = onEvent
        DispatchQueue.main.async {
            sender(["type": "route", "route": route])
        }

        if reason == .oldDeviceUnavailable && route == "speaker" && isRunning {
            let previousRoute =
                info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let wasBluetooth = previousRoute?.outputs.contains {
                $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
                    || $0.portType == .bluetoothLE
            } ?? false
            pauseForInterruption(reason: wasBluetooth ? "bluetoothDisconnected" : "routeBecameUnsafe")
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        if type == .began {
            pauseForInterruption(reason: "systemAudioInterruption")
        } else if type == .ended && pausedByInterruption {
            let sender = onEvent
            DispatchQueue.main.async {
                sender(["type": "resumed"])
            }
        }
    }
}
