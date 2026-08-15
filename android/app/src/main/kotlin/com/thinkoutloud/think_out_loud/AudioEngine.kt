package com.thinkoutloud.think_out_loud

import android.content.Context
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
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max

/**
 * Direct native input-to-output audio tap, per docs/audio-architecture.md:
 * VOICE_COMMUNICATION input source (avoids extra AEC/AGC/NS fighting the
 * passthrough) feeding a PERFORMANCE_MODE_LOW_LATENCY AudioTrack on a
 * dedicated thread. Dart only calls start/stop and reads level/route/
 * interruption events via [onEvent] — raw PCM never crosses the platform
 * channel.
 *
 * This uses the framework AudioRecord/AudioTrack low-latency ("FAST
 * track") path rather than hand-rolled AAudio/Oboe JNI, so it builds with
 * the standard Android Gradle plugin only (no NDK/CMake toolchain
 * required) while still avoiding the Dart hot path. See the final report
 * for why measured round-trip latency could not be verified in this
 * sandboxed build environment (no physical device or headphones).
 */
class AudioEngine(
    private val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val CHANNEL_IN = AudioFormat.CHANNEL_IN_MONO
        private const val CHANNEL_OUT = AudioFormat.CHANNEL_OUT_MONO
        private const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
        private const val BYTES_PER_SAMPLE = 2
        private const val LEVEL_EVERY_N_BUFFERS = 5
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

    /** @throws SecurityException if RECORD_AUDIO isn't granted. */
    fun start(outputPath: String) {
        if (running.get()) return

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
        val targetBufBytes = nativeBufferFrames * BYTES_PER_SAMPLE * 4
        val recordBufBytes = max(minRecordBuf, targetBufBytes)
        val trackBufBytes = max(minTrackBuf, targetBufBytes)

        val newRecord = AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
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
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
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
        thread = Thread({ runLoop(bufferFrames) }, "AudioEngineThread").apply {
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
        running.set(false)
        thread?.join(500)
        thread = null
        releaseRecordAndTrack()

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
