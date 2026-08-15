package com.thinkoutloud.think_out_loud

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "think_out_loud/audio_engine"
    private val eventChannelName = "think_out_loud/audio_engine/events"

    private var engine: AudioEngine? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val audioEngine = AudioEngine(applicationContext) { event -> eventSink?.success(event) }
        engine = audioEngine

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                        eventSink = sink
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                }
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "currentRoute" -> result.success(audioEngine.currentRoute())
                    "start" -> {
                        val path = call.argument<String>("outputPath")
                        if (path == null) {
                            result.error("bad_args", "outputPath is required", null)
                        } else {
                            // Bluetooth routes negotiate SCO asynchronously, so
                            // the result is only sent once start() actually
                            // finishes (success or failure) via this callback —
                            // never call result.success/error before this.
                            audioEngine.start(path) { error ->
                                when (error) {
                                    null -> result.success(null)
                                    is SecurityException ->
                                        result.error("permission_denied", error.message, null)
                                    else -> result.error("engine_failure", error.message, null)
                                }
                            }
                        }
                    }
                    "stop" -> {
                        try {
                            audioEngine.stop()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("engine_failure", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        engine?.stop()
        super.onDestroy()
    }
}
