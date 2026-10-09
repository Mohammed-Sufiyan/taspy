package com.dfx.nfcpin

import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/**
 * Launched by Android's NFC dispatch when a card is tapped and the app is not scanning.
 * Transparent, so the Flutter popup (`tapMain` in main.dart) appears over whatever is on
 * screen, and it never shows up in Recents.
 */
class TapActivity : NfcFlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "tapMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent
}
