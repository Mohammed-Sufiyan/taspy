package com.dfx.nfcpin

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Wires [NfcBridge] into the activity lifecycle. Shared by the main app and the tap popup.
 * A FragmentActivity because local_auth shows the system BiometricPrompt as a fragment.
 */
abstract class NfcFlutterActivity : FlutterFragmentActivity() {
    private var nfc: NfcBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nfc = NfcBridge(this, flutterEngine.dartExecutor.binaryMessenger).also {
            // Runs during onCreate: if a card tap launched us, this is that tap.
            it.handleIntent(intent, coldStart = true)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        nfc?.handleIntent(intent, coldStart = false)
    }

    @Deprecated("Needed for the contact picker result")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (nfc?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onResume() {
        super.onResume()
        nfc?.onResume()
    }

    override fun onPause() {
        nfc?.onPause()
        super.onPause()
    }

    override fun onStop() {
        nfc?.onStop()
        super.onStop()
    }

    override fun onDestroy() {
        nfc?.dispose()
        nfc = null
        super.onDestroy()
    }
}
