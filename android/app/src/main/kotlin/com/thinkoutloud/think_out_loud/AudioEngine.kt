package com.thinkoutloud.think_out_loud

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max

/**
 * Direct native input-to-output audio tap, per docs/audio-architecture.md:
 * VOICE_RECOGNITION input source (AGC/NS off by default, unlike
 * VOICE_COMMUNICATION, so the passthrough isn't quietly clamped) feeding
 * a PERFORMANCE_MODE_LOW_LATENCY AudioTrack on a dedicated thread with
 * real-time audio scheduling. Dart only calls start/stop and reads
 * level/route/interruption events via [onEvent] — raw PCM never crosses
 * the platform channel.
 *
 * Bluetooth note: A2DP (what carries earbuds' audio *output*) is
 * one-way. Capturing *input* from a Bluetooth headset's mic requires
 * explicitly negotiating the SCO link (`startBluetoothSco`) — without
 * it, AudioRecord silently falls back to the phone's body mic even
 * while output plays through the earbuds. SCO is a Bluetooth Classic
 * voice-call profile: it has its own inherent latency and bandwidth
 * ceiling (narrowband codec) that no amount of buffer tuning here can
 * remove — wired headphones will always be snappier and clearer than a
 * fully Bluetooth (mic + earbuds) setup. See startWithBluetoothSco().
 *
 * This uses the framework AudioRecord/AudioTrack low-latency ("FAST
 * track") path rather than hand-rolled AAudio/Oboe JNI, so it builds with
 * the standard Android Gradle plugin only (no NDK/CMake toolchain
 * required) while still avoiding the Dart hot path.
 */
class AudioEngine(
    private val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val TAG = "AudioEngine"
        private const val CHANNEL_IN = AudioFormat.CHANNEL_IN_MONO
        private const val CHANNEL_OUT = AudioFormat.CHANNEL_OUT_MONO
        private const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
        private const val BYTES_PER_SAMPLE = 2
        private const val LEVEL_EVERY_N_BUFFERS = 5
        private const val SCO_CONNECT_TIMEOUT_MS = 4000L
        // Some OEM stacks (seen on MIUI) fire SCO_AUDIO_STATE_CONNECTED
        // slightly before the SCO audio path is actually ready to open,
        // so an immediate AudioRecord/AudioTrack init can fail. One short
        // retry absorbs that race without a full failure+manual-retry
        // cycle.
        private const val SCO_READY_RETRY_DELAY_MS = 300L
    }

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var record: AudioRecord? = null
    private var track: AudioTrack? = null
    private var thread: Thread? = null
    private val running = AtomicBoolean(false)
    private var pausedByInterruption = false

    private var outputFile: RandomAccessFile? = null
    private var dataBytesWritten: Long = 0
    private var sampleRate: Int = 48000

    private var focusRequest: AudioFocusRequest? = null
    private var deviceCallback: AudioDeviceCallback? = null

    private var scoActive = false
    private var scoAttemptInFlight = false
    private var scoReceiver: BroadcastReceiver? = null
    private var scoTimeoutRunnable: Runnable? = null

    private fun scoStateName(state: Int): String = when (state) {
        AudioManager.SCO_AUDIO_STATE_CONNECTED -> "CONNECTED"
        AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> "DISCONNECTED"
        AudioManager.SCO_AUDIO_STATE_CONNECTING -> "CONNECTING"
        AudioManager.SCO_AUDIO_STATE_ERROR -> "ERROR"
        else -> "UNKNOWN($state)"
    }

    fun currentRoute(): String {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        var sawBluetooth = false
        var sawWired = false
        for (d in outputs) {
            when (d.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO ->
                    sawBluetooth = true
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_USB_HEADSET -> sawWired = true
            }
        }
        return when {
            sawBluetooth -> "bluetooth"
            sawWired -> "headphones"
            else -> "speaker"
        }
    }

    /**
     * @param onResult called exactly once, on the main thread, with `null`
     *   on success or the failure cause. Bluetooth routes negotiate SCO
     *   asynchronously (~1-3s) before the engine actually starts; wired/
     *   speaker routes start synchronously and call back immediately.
     */
    fun start(outputPath: String, onResult: (Throwable?) -> Unit) {
        val route = currentRoute()
        Log.d(TAG, "start() route=$route running=${running.get()} scoAttemptInFlight=$scoAttemptInFlight")
        if (running.get()) {
            onResult(null)
            return
        }
        if (route == "bluetooth") {
            if (scoAttemptInFlight) {
                // Without this guard, a second concurrent attempt would
                // register its own receiver/timeout and call
                // stopBluetoothSco() out from under the first one,
                // producing exactly the rapid start/stop/start/stop
                // cycling seen in the field — fail fast and loud instead.
                Log.w(TAG, "start() called while a Bluetooth SCO connection attempt is already in flight; rejecting")
                onResult(IllegalStateException("Already connecting to the Bluetooth microphone"))
                return
            }
            startWithBluetoothSco(outputPath, onResult)
        } else {
            try {
                startEngineInternal(outputPath)
                onResult(null)
            } catch (e: Exception) {
                Log.e(TAG, "startEngineInternal failed (route=$route)", e)
                onResult(e)
            }
        }
    }

    /**
     * A2DP (Bluetooth earbuds' normal audio *output* profile) is
     * one-way — it carries no microphone signal. Getting input from a
     * Bluetooth headset's mic requires explicitly bringing up the SCO
     * link first; skipping this is why input silently falls back to the
     * phone's own mic. SCO is asynchronous (the headset has to
     * acknowledge over the air) and is a narrowband voice-call codec, so
     * it's also the reason a Bluetooth-mic session has a firm latency
     * and quality floor that a wired session doesn't.
     */
    private fun startWithBluetoothSco(outputPath: String, onResult: (Throwable?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "startWithBluetoothSco: BLUETOOTH_CONNECT not granted")
            onResult(SecurityException("Bluetooth permission not granted"))
            return
        }

        scoAttemptInFlight = true

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                val state = intent.getIntExtra(
                    AudioManager.EXTRA_SCO_AUDIO_STATE,
                    AudioManager.SCO_AUDIO_STATE_ERROR,
                )
                Log.d(TAG, "ACTION_SCO_AUDIO_STATE_UPDATED -> ${scoStateName(state)}")
                when (state) {
                    AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
                        cleanupScoWait()
                        attemptEngineStartAfterScoConnected(outputPath, onResult, retriesLeft = 1)
                    }
                    AudioManager.SCO_AUDIO_STATE_ERROR, AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> {
                        cleanupScoWait()
                        teardownSco()
                        onResult(
                            IllegalStateException(
                                "Could not connect to the Bluetooth headset's microphone " +
                                    "(state=${scoStateName(state)})"
                            )
                        )
                    }
                }
            }
        }
        scoReceiver = receiver
        context.registerReceiver(receiver, IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED))

        val timeout = Runnable {
            Log.w(TAG, "Bluetooth SCO connect timed out after ${SCO_CONNECT_TIMEOUT_MS}ms")
            cleanupScoWait()
            teardownSco()
            onResult(
                IllegalStateException("Timed out connecting to the Bluetooth headset's microphone")
            )
        }
        scoTimeoutRunnable = timeout
        mainHandler.postDelayed(timeout, SCO_CONNECT_TIMEOUT_MS)

        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        audioManager.startBluetoothSco()
        @Suppress("DEPRECATION")
        audioManager.isBluetoothScoOn = true
        scoActive = true
        Log.d(TAG, "requested Bluetooth SCO connection")
    }

    /**
     * SCO_AUDIO_STATE_CONNECTED can fire slightly before the SCO audio
     * path is actually ready to open on some OEM stacks — retry once
     * after a short delay before treating it as a real failure.
     */
    private fun attemptEngineStartAfterScoConnected(
        outputPath: String,
        onResult: (Throwable?) -> Unit,
        retriesLeft: Int,
    ) {
        try {
            startEngineInternal(outputPath)
            Log.d(TAG, "engine started on Bluetooth SCO")
            onResult(null)
        } catch (e: Exception) {
            if (retriesLeft > 0) {
                Log.w(TAG, "engine start failed right after SCO connected, retrying once", e)
                mainHandler.postDelayed(
                    { attemptEngineStartAfterScoConnected(outputPath, onResult, retriesLeft - 1) },
                    SCO_READY_RETRY_DELAY_MS,
                )
            } else {
                Log.e(TAG, "engine start failed after SCO connected (no retries left)", e)
                teardownSco()
                onResult(e)
            }
        }
    }

    private fun cleanupScoWait() {
        scoAttemptInFlight = false
        scoTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        scoTimeoutRunnable = null
        scoReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        scoReceiver = null
    }

    private fun teardownSco() {
        if (!scoActive) return
        scoActive = false
        Log.d(TAG, "tearing down Bluetooth SCO")
        @Suppress("DEPRECATION")
        audioManager.stopBluetoothSco()
        @Suppress("DEPRECATION")
        audioManager.isBluetoothScoOn = false
        audioManager.mode = AudioManager.MODE_NORMAL
    }

    /** @throws IllegalStateException if AudioRecord/AudioTrack fail to initialize. */
    private fun startEngineInternal(outputPath: String) {
        sampleRate = readAudioManagerIntProperty(
            AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE,
            48000,
        )
        val nativeBufferFrames = readAudioManagerIntProperty(
            AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER,
            256,
        )

        val minRecordBuf = AudioRecord.getMinBufferSize(sampleRate, CHANNEL_IN, ENCODING)
        val minTrackBuf = AudioTrack.getMinBufferSize(sampleRate, CHANNEL_OUT, ENCODING)
        // 2x the platform's own reported low-latency buffer — enough for
        // double-buffering stability without adding avoidable delay.
        val targetBufBytes = nativeBufferFrames * BYTES_PER_SAMPLE * 2
        val recordBufBytes = max(minRecordBuf, targetBufBytes)
        val trackBufBytes = max(minTrackBuf, targetBufBytes)

        val newRecord = AudioRecord.Builder()
            // VOICE_RECOGNITION (not VOICE_COMMUNICATION): AGC/NS are off
            // by default, so the passthrough isn't quietly attenuated —
            // VOICE_COMMUNICATION is tuned for two-way calls and was
            // making monitored audio noticeably quieter than the source.
            .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(ENCODING)
                    .setSampleRate(sampleRate)
                    .setChannelMask(CHANNEL_IN)
                    .build()
            )
            .setBufferSizeInBytes(recordBufBytes)
            .build()

        val trackBuilder = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    // USAGE_MEDIA (not USAGE_VOICE_COMMUNICATION): routes
                    // through the normal media volume stream that the
                    // volume rocker actually controls, instead of the
                    // separate in-call stream, which defaults much
                    // quieter outside of an actual phone call.
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(ENCODING)
                    .setSampleRate(sampleRate)
                    .setChannelMask(CHANNEL_OUT)
                    .build()
            )
            .setBufferSizeInBytes(trackBufBytes)
            .setTransferMode(AudioTrack.MODE_STREAM)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            trackBuilder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        }
        val newTrack = trackBuilder.build()

        if (newRecord.state != AudioRecord.STATE_INITIALIZED ||
            newTrack.state != AudioTrack.STATE_INITIALIZED
        ) {
            newRecord.release()
            newTrack.release()
            throw IllegalStateException("Failed to initialize AudioRecord/AudioTrack")
        }

        if (outputFile == null) {
            val file = File(outputPath)
            file.parentFile?.mkdirs()
            val raf = RandomAccessFile(file, "rw")
            raf.setLength(0)
            writeWavPlaceholderHeader(raf, sampleRate)
            outputFile = raf
            dataBytesWritten = 0
        }

        record = newRecord
        track = newTrack
        pausedByInterruption = false
        running.set(true)

        requestAudioFocus()
        registerDeviceCallback()

        newRecord.startRecording()
        newTrack.play()

        val bufferFrames = recordBufBytes / BYTES_PER_SAMPLE
        thread = Thread({
            // Real-time audio scheduling class, not just a high Java
            // thread priority — this is what actually keeps the OS from
            // preempting the hot loop and adding jitter/latency.
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            runLoop(bufferFrames)
        }, "AudioEngineThread").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    private fun runLoop(bufferFrames: Int) {
        val buffer = ShortArray(bufferFrames)
        var bufferCounter = 0
        while (running.get()) {
            val rec = record ?: break
            val trk = track ?: break
            val read = rec.read(buffer, 0, buffer.size)
            if (read <= 0) continue
            trk.write(buffer, 0, read)
            appendToFile(buffer, read)

            bufferCounter++
            if (bufferCounter % LEVEL_EVERY_N_BUFFERS == 0) {
                emitLevel(buffer, read)
            }
        }
    }

    private fun appendToFile(buffer: ShortArray, length: Int) {
        val raf = outputFile ?: return
        val bytes = ByteArray(length * BYTES_PER_SAMPLE)
        for (i in 0 until length) {
            val v = buffer[i].toInt()
            bytes[i * 2] = (v and 0xFF).toByte()
            bytes[i * 2 + 1] = ((v shr 8) and 0xFF).toByte()
        }
        synchronized(raf) {
            raf.seek(raf.length())
            raf.write(bytes)
        }
        dataBytesWritten += bytes.size
    }

    private fun emitLevel(buffer: ShortArray, length: Int) {
        var peak = 0
        for (i in 0 until length) {
            val v = abs(buffer[i].toInt())
            if (v > peak) peak = v
        }
        val level = (peak / 32767.0).coerceIn(0.0, 1.0)
        mainHandler.post { onEvent(mapOf("type" to "level", "level" to level)) }
    }

    fun stop() {
        cleanupScoWait()
        running.set(false)
        thread?.join(500)
        thread = null
        releaseRecordAndTrack()
        teardownSco()

        abandonAudioFocus()
        unregisterDeviceCallback()

        outputFile?.let { finalizeWavHeader(it, dataBytesWritten) }
        outputFile?.close()
        outputFile = null
        dataBytesWritten = 0
    }

    private fun pauseForInterruption(reason: String) {
        if (!running.get() || pausedByInterruption) return
        pausedByInterruption = true
        running.set(false)
        thread?.join(500)
        thread = null
        releaseRecordAndTrack()
        teardownSco()
        mainHandler.post { onEvent(mapOf("type" to "interruption", "reason" to reason)) }
    }

    private fun releaseRecordAndTrack() {
        try {
            record?.stop()
        } catch (_: Exception) {
        }
        try {
            track?.stop()
        } catch (_: Exception) {
        }
        record?.release()
        track?.release()
        record = null
        track = null
    }

    private fun requestAudioFocus() {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            when (change) {
                AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ->
                    pauseForInterruption("systemAudioInterruption")
                AudioManager.AUDIOFOCUS_GAIN ->
                    if (pausedByInterruption) {
                        mainHandler.post { onEvent(mapOf("type" to "resumed")) }
                    }
            }
        }
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setOnAudioFocusChangeListener(listener, mainHandler)
            .build()
        focusRequest = request
        audioManager.requestAudioFocus(request)
    }

    private fun abandonAudioFocus() {
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = null
    }

    private fun registerDeviceCallback() {
        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
                mainHandler.post { onEvent(mapOf("type" to "route", "route" to currentRoute())) }
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
                val removedWasHeadphone = removedDevices.any {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                        it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES
                }
                val route = currentRoute()
                mainHandler.post { onEvent(mapOf("type" to "route", "route" to route)) }
                if (removedWasHeadphone && route == "speaker") {
                    val wasBluetooth = removedDevices.any {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                    }
                    pauseForInterruption(
                        if (wasBluetooth) "bluetoothDisconnected" else "routeBecameUnsafe"
                    )
                }
            }
        }
        deviceCallback = callback
        audioManager.registerAudioDeviceCallback(callback, mainHandler)
    }

    private fun unregisterDeviceCallback() {
        deviceCallback?.let { audioManager.unregisterAudioDeviceCallback(it) }
        deviceCallback = null
    }

    private fun readAudioManagerIntProperty(key: String, fallback: Int): Int {
        return try {
            audioManager.getProperty(key)?.toIntOrNull() ?: fallback
        } catch (_: Exception) {
            fallback
        }
    }

    // -- Minimal WAV (PCM16 mono) header handling; finalized on stop() so
    // playback works even though total length isn't known up front. --

    private fun writeWavPlaceholderHeader(raf: RandomAccessFile, sampleRate: Int) {
        raf.seek(0)
        raf.writeBytes("RIFF")
        raf.write(intToLE(0))
        raf.writeBytes("WAVE")
        raf.writeBytes("fmt ")
        raf.write(intToLE(16))
        raf.write(shortToLE(1))
        raf.write(shortToLE(1))
        raf.write(intToLE(sampleRate))
        raf.write(intToLE(sampleRate * BYTES_PER_SAMPLE))
        raf.write(shortToLE(BYTES_PER_SAMPLE))
        raf.write(shortToLE(16))
        raf.writeBytes("data")
        raf.write(intToLE(0))
    }

    private fun finalizeWavHeader(raf: RandomAccessFile, dataBytes: Long) {
        val riffSize = 36 + dataBytes
        raf.seek(4)
        raf.write(intToLE(riffSize.toInt()))
        raf.seek(40)
        raf.write(intToLE(dataBytes.toInt()))
    }

    private fun intToLE(v: Int): ByteArray = byteArrayOf(
        (v and 0xFF).toByte(),
        ((v shr 8) and 0xFF).toByte(),
        ((v shr 16) and 0xFF).toByte(),
        ((v shr 24) and 0xFF).toByte(),
    )

    private fun shortToLE(v: Int): ByteArray = byteArrayOf(
        (v and 0xFF).toByte(),
        ((v shr 8) and 0xFF).toByte(),
    )
}
