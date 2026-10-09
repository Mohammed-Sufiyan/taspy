package com.dfx.nfcpin

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.NfcA
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.security.SecureRandom

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
        private val NFC_ACTIONS = setOf(
            NfcAdapter.ACTION_NDEF_DISCOVERED,
            NfcAdapter.ACTION_TECH_DISCOVERED,
            NfcAdapter.ACTION_TAG_DISCOVERED,
        )
    }
}
