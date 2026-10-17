package com.intercom.intercom_app

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val channelName = "intercom/audio"
    private var channel: MethodChannel? = null
    private lateinit var audioManager: AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var selectedKind: String = "speaker"

    // Mic / Recording test state
    @Volatile
    private var isMicTesting = false
    private var micThread: Thread? = null
    private var lastRecordedFile: File? = null
    private var mediaPlayer: MediaPlayer? = null

    @Volatile
    private var gateEnabled: Boolean = true
    @Volatile
    private var gateThreshold: Double = 0.03

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
            mainHandler.post {
                channel?.invokeMethod("onAudioDevicesChanged", listAudioOutputs())
            }
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
            mainHandler.post {
                channel?.invokeMethod("onAudioDevicesChanged", listAudioOutputs())
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "listAudioOutputs" -> result.success(listAudioOutputs())
                "selectAudioOutput" -> {
                    val kind = call.argument<String>("kind") ?: "speaker"
                    val ok = selectAudioOutput(kind)
                    result.success(ok)
                }
                "startMicTest" -> {
                    startMicTest(call)
                    result.success(true)
                }
                "updateMicTestGate" -> {
                    gateEnabled = call.argument<Boolean>("noiseGateEnabled") ?: true
                    gateThreshold = call.argument<Double>("noiseGateThreshold") ?: 0.03
                    result.success(true)
                }
                "stopMicTest" -> {
                    val info = stopMicTest()
                    result.success(info)
                }
                "playRecordedTest" -> {
                    val ok = playRecordedTest()
                    result.success(ok)
                }
                "stopPlayback" -> {
                    stopPlayback()
                    result.success(true)
                }
                "readStore" -> {
                    val file = File(filesDir, "intercom_store.json")
                    val text = if (file.exists()) file.readText(Charsets.UTF_8) else null
                    result.success(text)
                }
                "writeStore" -> {
                    val json = call.argument<String>("json") ?: "{}"
                    val file = File(filesDir, "intercom_store.json")
                    file.writeText(json, Charsets.UTF_8)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopMicTest()
        stopPlayback()
        try {
            audioManager.unregisterAudioDeviceCallback(deviceCallback)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun listAudioOutputs(): List<Map<String, Any>> {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        var hasEarpiece = false
        var hasWired = false
        var wiredName = "有線イヤホン / ヘッドセット"
        var hasBluetooth = false
        var btName = "Bluetoothヘッドセット"

        for (d in outputs) {
            when (d.type) {
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> hasEarpiece = true
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE -> {
                    hasWired = true
                    val pName = d.productName?.toString()?.trim()
                    if (!pName.isNullOrEmpty() && pName != Build.MODEL) {
                        wiredName = "有線 ($pName)"
                    }
                }
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> {
                    hasBluetooth = true
                    val pName = d.productName?.toString()?.trim()
                    if (!pName.isNullOrEmpty()) {
                        btName = "Bluetooth ($pName)"
                    }
                }
            }
        }

        val currentKind = detectCurrentActiveKind(hasBluetooth, hasWired)
        val result = mutableListOf<Map<String, Any>>()

        result.add(
            mapOf(
                "kind" to "speaker",
                "name" to "スピーカー",
                "active" to (currentKind == "speaker")
            )
        )
        if (hasEarpiece) {
            result.add(
                mapOf(
                    "kind" to "earpiece",
                    "name" to "受話口 (耳元)",
                    "active" to (currentKind == "earpiece")
                )
            )
        }
        if (hasWired) {
            result.add(
                mapOf(
                    "kind" to "wired",
                    "name" to wiredName,
                    "active" to (currentKind == "wired")
                )
            )
        }
        if (hasBluetooth) {
            result.add(
                mapOf(
                    "kind" to "bluetooth",
                    "name" to btName,
                    "active" to (currentKind == "bluetooth")
                )
            )
        }
        return result
    }

    private fun detectCurrentActiveKind(hasBluetooth: Boolean, hasWired: Boolean): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val comm = audioManager.communicationDevice
            if (comm != null) {
                return when (comm.type) {
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
                    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_USB_HEADSET,
                    AudioDeviceInfo.TYPE_USB_DEVICE -> "wired"
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetooth"
                    else -> selectedKind
                }
            }
        }
        if (selectedKind == "bluetooth" && hasBluetooth) return "bluetooth"
        if (selectedKind == "wired" && hasWired) return "wired"
        return selectedKind
    }

    @Suppress("DEPRECATION")
    private fun selectAudioOutput(kind: String): Boolean {
        selectedKind = kind
        return try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val devices = audioManager.availableCommunicationDevices
                val target = devices.firstOrNull { d ->
                    when (kind) {
                        "speaker" -> d.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                        "earpiece" -> d.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                        "wired" -> d.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                                d.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                                d.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                                d.type == AudioDeviceInfo.TYPE_USB_DEVICE
                        "bluetooth" -> d.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                                d.type == AudioDeviceInfo.TYPE_BLE_HEADSET
                        else -> false
                    }
                }
                if (target != null) {
                    audioManager.setCommunicationDevice(target)
                } else if (kind == "speaker") {
                    audioManager.clearCommunicationDevice()
                    audioManager.isSpeakerphoneOn = true
                } else if (kind == "earpiece") {
                    audioManager.clearCommunicationDevice()
                    audioManager.isSpeakerphoneOn = false
                }
            } else {
                when (kind) {
                    "bluetooth" -> {
                        audioManager.isSpeakerphoneOn = false
                        audioManager.startBluetoothSco()
                        audioManager.isBluetoothScoOn = true
                    }
                    "speaker" -> {
                        audioManager.isBluetoothScoOn = false
                        audioManager.stopBluetoothSco()
                        audioManager.isSpeakerphoneOn = true
                    }
                    else -> {
                        audioManager.isBluetoothScoOn = false
                        audioManager.stopBluetoothSco()
                        audioManager.isSpeakerphoneOn = false
                    }
                }
            }
            mainHandler.post {
                channel?.invokeMethod("onAudioDevicesChanged", listAudioOutputs())
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun startMicTest(call: MethodCall) {
        stopMicTest()
        stopPlayback()

        val recordToFile = call.argument<Boolean>("recordToFile") ?: false
        val useNs = call.argument<Boolean>("noiseSuppression") ?: true
        val useAec = call.argument<Boolean>("echoCancellation") ?: true
        val useAgc = call.argument<Boolean>("autoGainControl") ?: true
        gateEnabled = call.argument<Boolean>("noiseGateEnabled") ?: true
        gateThreshold = call.argument<Double>("noiseGateThreshold") ?: 0.03

        isMicTesting = true
        val sampleRate = 16000
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(3200)

        micThread = Thread {
            var recorder: AudioRecord? = null
            var ns: NoiseSuppressor? = null
            var aec: AcousticEchoCanceler? = null
            var agc: AutomaticGainControl? = null
            val pcmOut = if (recordToFile) ByteArrayOutputStream() else null

            try {
                recorder = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    minBuf * 2
                )
                val sessionId = recorder.audioSessionId
                if (NoiseSuppressor.isAvailable()) {
                    ns = NoiseSuppressor.create(sessionId)?.apply { enabled = useNs }
                }
                if (AcousticEchoCanceler.isAvailable()) {
                    aec = AcousticEchoCanceler.create(sessionId)?.apply { enabled = useAec }
                }
                if (AutomaticGainControl.isAvailable()) {
                    agc = AutomaticGainControl.create(sessionId)?.apply { enabled = useAgc }
                }

                recorder.startRecording()
                val chunkSamples = 1600 // 100ms @ 16kHz
                val buf = ShortArray(chunkSamples)
                var holdTicks = 0
                val maxRecordBytes = sampleRate * 2 * 15 // max 15 seconds

                while (isMicTesting) {
                    val read = recorder.read(buf, 0, chunkSamples)
                    if (read <= 0) continue

                    var sumSq = 0.0
                    for (i in 0 until read) {
                        val norm = buf[i] / 32768.0
                        sumSq += norm * norm
                    }
                    val rms = sqrt(sumSq / read)
                    // Scale RMS so normal speech is around 0.15 - 0.60
                    val level = (rms * 3.0).coerceIn(0.0, 1.0)

                    val isOpen = if (!gateEnabled) {
                        true
                    } else if (level >= gateThreshold) {
                        holdTicks = 4 // hold open for 400ms after speech drops below threshold
                        true
                    } else if (holdTicks > 0) {
                        holdTicks--
                        true
                    } else {
                        false
                    }

                    if (pcmOut != null && pcmOut.size() < maxRecordBytes) {
                        val byteBuf = ByteBuffer.allocate(read * 2).order(ByteOrder.LITTLE_ENDIAN)
                        for (i in 0 until read) {
                            byteBuf.putShort(if (isOpen) buf[i] else 0)
                        }
                        pcmOut.write(byteBuf.array())
                    }

                    mainHandler.post {
                        if (isMicTesting) {
                            channel?.invokeMethod(
                                "onMicTestLevel",
                                mapOf("level" to level, "gateOpen" to isOpen)
                            )
                        }
                    }
                }

                if (pcmOut != null && pcmOut.size() > 0) {
                    val wavFile = File(cacheDir, "mic_test.wav")
                    writeWavFile(wavFile, pcmOut.toByteArray(), sampleRate)
                    lastRecordedFile = wavFile
                }
            } catch (_: Exception) {
            } finally {
                try {
                    ns?.release()
                    aec?.release()
                    agc?.release()
                    recorder?.stop()
                    recorder?.release()
                } catch (_: Exception) {}
            }
        }.apply { start() }
    }

    private fun stopMicTest(): Map<String, Any?> {
        isMicTesting = false
        try {
            micThread?.join(600)
        } catch (_: Exception) {}
        micThread = null
        val file = lastRecordedFile
        val exists = file != null && file.exists() && file.length() > 44
        val durationMs = if (exists) ((file!!.length() - 44) * 1000L) / (16000 * 2) else 0L
        return mapOf(
            "hasRecording" to exists,
            "durationMs" to durationMs
        )
    }

    private fun playRecordedTest(): Boolean {
        stopPlayback()
        val file = lastRecordedFile ?: return false
        if (!file.exists() || file.length() <= 44) return false
        return try {
            val mp = MediaPlayer()
            mediaPlayer = mp
            mp.setDataSource(file.absolutePath)
            mp.setOnCompletionListener {
                mainHandler.post {
                    channel?.invokeMethod("onPlaybackCompleted", null)
                }
            }
            mp.prepare()
            mp.start()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun stopPlayback() {
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {}
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
    }

    private fun writeWavFile(file: File, pcmData: ByteArray, sampleRate: Int) {
        val totalDataLen = pcmData.size + 36
        val byteRate = sampleRate * 2
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt(totalDataLen)
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16) // PCM chunk size
        header.putShort(1) // AudioFormat = 1 (PCM)
        header.putShort(1) // Channels = 1 (Mono)
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort(2) // BlockAlign
        header.putShort(16) // BitsPerSample
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(pcmData.size)

        FileOutputStream(file).use { fos ->
            fos.write(header.array())
            fos.write(pcmData)
        }
    }
}
