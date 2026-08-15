import Flutter
import UIKit

// See AudioEngine.swift for the caveat: this wiring could not be built or
// run in this sandboxed Linux environment (no Xcode/macOS available),
// unlike the Android path, which was verified with `flutter build apk`.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let methodChannelName = "think_out_loud/audio_engine"
  private let eventChannelName = "think_out_loud/audio_engine/events"

  private var audioEngine: AudioEngine?
  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioEngine")
    let messenger = registrar.messenger()

    let engine = AudioEngine { [weak self] event in
      self?.eventSink?(event)
    }
    audioEngine = engine

    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(
      EngineStreamHandler(
        onListen: { [weak self] sink in self?.eventSink = sink },
        onCancel: { [weak self] in self?.eventSink = nil }
      ))

    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self, let engine = self.audioEngine else {
        result(FlutterError(code: "no_engine", message: "Audio engine unavailable", details: nil))
        return
      }
      switch call.method {
      case "currentRoute":
        result(engine.currentRoute())
      case "start":
        guard let args = call.arguments as? [String: Any],
          let path = args["outputPath"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "outputPath is required", details: nil))
          return
        }
        do {
          try engine.start(outputPath: path)
          result(nil)
        } catch AudioEngine.EngineError.permissionDenied {
          result(FlutterError(code: "permission_denied", message: "Microphone permission not granted", details: nil))
        } catch {
          result(FlutterError(code: "engine_failure", message: "\(error)", details: nil))
        }
      case "stop":
        engine.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private final class EngineStreamHandler: NSObject, FlutterStreamHandler {
  private let onListenCallback: (@escaping FlutterEventSink) -> Void
  private let onCancelCallback: () -> Void

  init(onListen: @escaping (@escaping FlutterEventSink) -> Void, onCancel: @escaping () -> Void) {
    self.onListenCallback = onListen
    self.onCancelCallback = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    onListenCallback(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelCallback()
    return nil
  }
}
