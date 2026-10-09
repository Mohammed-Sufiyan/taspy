package com.dfx.nfcpin

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.NfcA
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.view.WindowManager
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Native NFC layer for the compatibility test.
 *
 * Privacy: raw card identifiers never leave this class. Flutter only receives a salted,
 * truncated SHA-256 fingerprint, which is enough to tell whether two taps produced the
 * same ID. No APDUs are sent, so no payment data (card number, expiry, etc.) is ever read.
 */
class NfcBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val adapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)
    private val main = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "nfcpin/nfc")
    private val events = EventChannel(messenger, "nfcpin/nfc_events")

    private var sink: EventChannel.EventSink? = null
    // Events raised before Dart subscribes (e.g. the tap that launched the app).
    private val pending = mutableListOf<Map<String, Any?>>()

    private var scanning = false
    private var resumed = false
    private var stopped = false
    private var receiverRegistered = false

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            emit(status() + ("type" to "status"))
        }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    // ---- Activity lifecycle -------------------------------------------------------------

    fun onResume() {
        resumed = true
        stopped = false
        if (scanning) enableReader()
        if (!receiverRegistered) {
            val filter = IntentFilter(NfcAdapter.ACTION_ADAPTER_STATE_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(stateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity.registerReceiver(stateReceiver, filter)
            }
            receiverRegistered = true
        }
    }

    fun onPause() {
        // Reader mode only works while the activity is in the foreground.
        disableReader()
        resumed = false
        if (receiverRegistered) {
            activity.unregisterReceiver(stateReceiver)
            receiverRegistered = false
        }
    }

    fun onStop() {
        stopped = true
    }

    fun dispose() {
        sounds?.release()
        sounds = null
        scanning = false
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    /**
     * Handles a tag delivered by Android's NFC dispatch (manifest TECH_DISCOVERED filter).
     * [coldStart] is true when the tap created the activity.
     */
    fun handleIntent(intent: Intent?, coldStart: Boolean) {
        if (intent == null || intent.action !in NFC_ACTIONS) return
        // Reopening from Recents redelivers the original launch intent; that is not a tap.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        if (intent.getBooleanExtra(EXTRA_HANDLED, false)) return
        intent.putExtra(EXTRA_HANDLED, true)

        val tag = tagFrom(intent) ?: return
        val source = when {
            coldStart -> "launch_closed"
            stopped -> "launch_background"
            else -> "tap_while_open"
        }
        emit(describe(tag, source))
    }

    // ---- Channels -----------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(status())
            "startScan" -> {
                val a = adapter
                when {
                    a == null -> result.error("unavailable", "No NFC hardware", null)
                    !a.isEnabled -> result.error("disabled", "NFC is turned off", null)
                    else -> {
                        scanning = true
                        if (resumed) enableReader()
                        result.success(null)
                    }
                }
            }
            "stopScan" -> {
                scanning = false
                disableReader()
                result.success(null)
            }
            "openSettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                } catch (e: Exception) {
                    activity.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                }
                result.success(null)
            }
            "getSettings" -> result.success(
                mapOf(
                    "sound" to settings().getBoolean("sound", true),
                    "onboarded" to settings().getBoolean("onboarded", false),
                    "appLock" to settings().getBoolean("appLock", false),
                ),
            )
            "setSetting" -> {
                val key = call.argument<String>("key")
                val value = call.argument<Boolean>("value")
                if (key !in SETTING_KEYS || value == null) {
                    result.error("bad_args", "Unknown setting", null)
                } else {
                    settings().edit().putBoolean(key, value).apply()
                    result.success(null)
                }
            }
            "setSecure" -> {
                // Blocks screenshots/screen recording and blanks the Recents thumbnail.
                if (call.argument<Boolean>("secure") == true) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
            "encrypt" -> try {
                result.success(encrypt(call.argument<String>("text") ?: ""))
            } catch (e: Exception) {
                result.error("crypto", e.javaClass.simpleName, null)
            }
            "decrypt" -> try {
                result.success(decrypt(call.argument<String>("data") ?: ""))
            } catch (e: Exception) {
                result.error("crypto", e.javaClass.simpleName, null)
            }
            "playTapSound" -> {
                playTapSound()
                result.success(null)
            }
            "close" -> {
                activity.finish()
                result.success(null)
            }
            "openApp" -> {
                activity.startActivity(
                    Intent(activity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                activity.finish()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        pending.forEach(events::success)
        pending.clear()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // ---- Internals ----------------------------------------------------------------------

    private fun enableReader() {
        val a = adapter ?: return
        val flags = NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V
        try {
            a.enableReaderMode(activity, { tag -> main.post { emit(describe(tag, "foreground_scan")) } }, flags, null)
        } catch (e: IllegalStateException) {
            // Activity not in the foreground; onResume will retry while [scanning] is set.
        }
    }

    private fun disableReader() {
        try {
            adapter?.disableReaderMode(activity)
        } catch (e: IllegalStateException) {
            // Already gone with the activity.
        }
    }

    private fun status(): Map<String, Any?> = mapOf(
        "hardware" to (adapter != null),
        "enabled" to (adapter?.isEnabled == true),
        "device" to if (Build.MODEL.startsWith(Build.MANUFACTURER, ignoreCase = true)) {
            Build.MODEL
        } else {
            "${Build.MANUFACTURER} ${Build.MODEL}"
        },
        "androidVersion" to Build.VERSION.RELEASE,
        "sdkInt" to Build.VERSION.SDK_INT,
    )

    private fun describe(tag: Tag, source: String): Map<String, Any?> {
        val id = tag.id ?: ByteArray(0)
        val nfcA = NfcA.get(tag)
        return mapOf(
            "type" to "tag",
            "source" to source,
            "techs" to tag.techList.map { it.substringAfterLast('.') },
            "fingerprint" to fingerprint(id),
            "idLength" to id.size,
            // ISO/IEC 14443-3: a 4-byte NFC-A UID starting with 0x08 is randomly generated.
            "randomIdHint" to (id.size == 4 && id[0] == 0x08.toByte()),
            "atqa" to nfcA?.atqa?.toHex(),
            "sak" to nfcA?.sak?.toInt(),
            "timestampMs" to System.currentTimeMillis(),
        )
    }

    private fun fingerprint(id: ByteArray): String? {
        if (id.isEmpty()) return null
        val digest = MessageDigest.getInstance("SHA-256").run {
            update(salt())
            digest(id)
        }
        return digest.copyOf(6).toHex().chunked(4).joinToString("-")
    }

    /** Per-install random salt, so fingerprints are useless outside this install. */
    private fun salt(): ByteArray {
        val prefs = activity.getSharedPreferences("nfcpin_diagnostics", Context.MODE_PRIVATE)
        prefs.getString("salt", null)?.let { return Base64.decode(it, Base64.NO_WRAP) }
        val fresh = ByteArray(16).also { SecureRandom().nextBytes(it) }
        prefs.edit().putString("salt", Base64.encodeToString(fresh, Base64.NO_WRAP)).apply()
        return fresh
    }

    // ---- Storage encryption ----------------------------------------------------------

    /**
     * AES-256-GCM key generated inside the Android Keystore (hardware-backed where the
     * phone supports it). The key material never leaves the Keystore. It is not bound to
     * user authentication, so the tap popup can still read cards without a prompt.
     */
    private fun storageKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    /** Returns base64(iv || ciphertext+tag). */
    private fun encrypt(text: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, storageKey())
        val out = cipher.iv + cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(out, Base64.NO_WRAP)
    }

    private fun decrypt(data: String): String {
        val bytes = Base64.decode(data, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            storageKey(),
            GCMParameterSpec(128, bytes.copyOfRange(0, GCM_IV_BYTES)),
        )
        return String(cipher.doFinal(bytes, GCM_IV_BYTES, bytes.size - GCM_IV_BYTES), Charsets.UTF_8)
    }

    private fun settings() =
        activity.getSharedPreferences("tapsy_settings", Context.MODE_PRIVATE)

    private var sounds: SoundPool? = null
    private var chimeId = 0
    private var chimeReady = false

    /** Plays the tap chime unless the user turned it off or the phone is on silent/vibrate. */
    private fun playTapSound() {
        if (!settings().getBoolean("sound", true)) return
        val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val pool = sounds ?: SoundPool.Builder()
            .setMaxStreams(1)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
            .also { sounds = it }
        if (chimeReady) {
            pool.play(chimeId, 0.8f, 0.8f, 1, 0, 1f)
        } else {
            pool.setOnLoadCompleteListener { p, id, status ->
                if (status == 0) {
                    chimeReady = true
                    p.play(id, 0.8f, 0.8f, 1, 0, 1f)
                }
            }
            chimeId = pool.load(activity, R.raw.tap_chime, 1)
        }
    }

    private fun emit(event: Map<String, Any?>) {
        val s = sink
        if (s == null) pending.add(event) else s.success(event)
    }

    @Suppress("DEPRECATION")
    private fun tagFrom(intent: Intent): Tag? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(NfcAdapter.EXTRA_TAG, Tag::class.java)
        } else {
            intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
        }

    private fun ByteArray.toHex() = joinToString("") { "%02x".format(it) }

    companion object {
        private const val EXTRA_HANDLED = "com.dfx.nfcpin.HANDLED"
        private val SETTING_KEYS = setOf("sound", "onboarded", "appLock")
        private const val KEY_ALIAS = "tapsy_storage_v1"
        private const val GCM_IV_BYTES = 12
        private val NFC_ACTIONS = setOf(
            NfcAdapter.ACTION_NDEF_DISCOVERED,
            NfcAdapter.ACTION_TECH_DISCOVERED,
            NfcAdapter.ACTION_TAG_DISCOVERED,
        )
    }
}
