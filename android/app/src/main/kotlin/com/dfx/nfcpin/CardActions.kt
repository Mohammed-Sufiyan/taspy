package com.dfx.nfcpin

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Handler
import android.provider.AlarmClock
import android.provider.ContactsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Runs the actions a card can trigger (see `card_action.dart`).
 *
 * Everything goes through standard Android intents, so the user stays in control:
 * calls open the dialer and WhatsApp opens the chat, both still needing a press to send.
 * Only https links are opened. Nothing is logged.
 */
class CardActions(private val activity: Activity, private val main: Handler) {

    private var contactResult: MethodChannel.Result? = null

    /** Replies with a result code: ok, on, off, not_found, unsupported, busy, blocked, failed. */
    fun run(call: MethodCall, result: MethodChannel.Result) {
        val value = call.argument<String>("value") ?: ""
        val label = call.argument<String>("label") ?: ""
        val extra = call.argument<String>("extra") ?: ""
        try {
            when (call.argument<String>("type")) {
                "openApp" -> {
                    val launch = activity.packageManager.getLaunchIntentForPackage(value)
                    if (launch == null) {
                        result.success("not_found")
                        return
                    }
                    start(launch)
                }
                "openLink" -> {
                    val uri = Uri.parse(value)
                    if (uri.scheme != "https" || uri.host.isNullOrEmpty()) {
                        result.success("blocked")
                        return
                    }
                    start(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                }
                // ACTION_DIAL only fills in the number; the user presses call.
                "call" -> start(Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", value, null)))
                // Opens the chat with the text typed in; the user presses send.
                "whatsapp" -> {
                    val digits = value.filter(Char::isDigit)
                    val text = if (extra.isBlank()) "" else "?text=" + Uri.encode(extra)
                    start(Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$digits$text")))
                }
                "navigate" -> try {
                    start(
                        Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=" + Uri.encode(value)))
                            .setPackage(MAPS_PACKAGE),
                    )
                } catch (e: ActivityNotFoundException) {
                    // No Google Maps: let the browser or another maps app handle it.
                    start(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse(
                                "https://www.google.com/maps/dir/?api=1&destination=" + Uri.encode(value),
                            ),
                        ),
                    )
                }
                "copyText" -> {
                    val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("Tapsy", value))
                }
                "timer" -> {
                    val minutes = value.toIntOrNull()
                    if (minutes == null || minutes !in 1..1440) {
                        result.success("failed")
                        return
                    }
                    val timer = Intent(AlarmClock.ACTION_SET_TIMER)
                        .putExtra(AlarmClock.EXTRA_LENGTH, minutes * 60)
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                    if (label.isNotBlank()) timer.putExtra(AlarmClock.EXTRA_MESSAGE, label)
                    start(timer)
                }
                "flashlight" -> {
                    torch(value, result)
                    return
                }
                else -> {
                    result.error("bad_args", "Unknown action", null)
                    return
                }
            }
            result.success("ok")
        } catch (e: ActivityNotFoundException) {
            result.success("not_found")
        } catch (e: SecurityException) {
            result.success("blocked")
        } catch (e: Exception) {
            result.success("failed")
        }
    }

    /** Launchable apps (name, package, small PNG icon), loaded off the main thread. */
    fun listApps(result: MethodChannel.Result) {
        Thread {
            val apps = try {
                val pm = activity.packageManager
                val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(launcher, 0)
                    .map { it.activityInfo }
                    .filter { it.packageName != activity.packageName }
                    .distinctBy { it.packageName }
                    .map { info ->
                        mapOf(
                            "package" to info.packageName,
                            "label" to info.loadLabel(pm).toString(),
                            "icon" to try {
                                png(info.loadIcon(pm))
                            } catch (e: Exception) {
                                null
                            },
                        )
                    }
                    .sortedBy { (it["label"] as String).lowercase() }
            } catch (e: Exception) {
                emptyList()
            }
            main.post { result.success(apps) }
        }.start()
    }

    /**
     * Opens the system contact picker. Android grants access to the one picked entry,
     * so Tapsy needs no contacts permission and never sees the rest of the list.
     */
    fun pickContact(result: MethodChannel.Result) {
        if (contactResult != null) {
            result.error("busy", "Picker already open", null)
            return
        }
        try {
            contactResult = result
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI),
                REQUEST_CONTACT,
            )
        } catch (e: ActivityNotFoundException) {
            contactResult = null
            result.success(null)
        }
    }

    /** Returns true if the result belonged to the contact picker. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CONTACT) return false
        val reply = contactResult ?: return true
        contactResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            reply.success(null)
            return true
        }
        val picked = try {
            activity.contentResolver.query(
                uri,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ),
                null,
                null,
                null,
            )?.use { c ->
                if (c.moveToFirst()) mapOf("phone" to c.getString(0), "name" to c.getString(1)) else null
            }
        } catch (e: Exception) {
            null
        }
        reply.success(picked)
        return true
    }

    fun dispose() {
        contactResult?.success(null)
        contactResult = null
    }

    // ---- Internals ----------------------------------------------------------------------

    private fun start(intent: Intent) {
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /**
     * Flashlight via CameraManager.setTorchMode (no camera permission needed). For
     * "toggle", the current state comes from a TorchCallback, which reports it right after
     * registering.
     */
    private fun torch(mode: String, result: MethodChannel.Result) {
        val cameras = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id = try {
            cameras.cameraIdList.firstOrNull {
                cameras.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        } catch (e: Exception) {
            null
        }
        if (id == null) {
            result.success("unsupported")
            return
        }

        fun set(on: Boolean) = try {
            cameras.setTorchMode(id, on)
            result.success(if (on) "on" else "off")
        } catch (e: Exception) {
            result.success("busy")
        }

        when (mode) {
            "on" -> set(true)
            "off" -> set(false)
            else -> {
                var done = false
                val callback = object : CameraManager.TorchCallback() {
                    override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
                        if (cameraId != id || done) return
                        done = true
                        cameras.unregisterTorchCallback(this)
                        set(!enabled)
                    }

                    override fun onTorchModeUnavailable(cameraId: String) {
                        if (cameraId != id || done) return
                        done = true
                        cameras.unregisterTorchCallback(this)
                        result.success("busy")
                    }
                }
                cameras.registerTorchCallback(callback, main)
                // Fallback if the phone never reports a state: assume it was off.
                main.postDelayed({
                    if (!done) {
                        done = true
                        cameras.unregisterTorchCallback(callback)
                        set(true)
                    }
                }, 600)
            }
        }
    }

    private fun png(drawable: Drawable): ByteArray {
        val bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, ICON_PX, ICON_PX)
        drawable.draw(canvas)
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }
    }

    companion object {
        private const val REQUEST_CONTACT = 4711
        private const val ICON_PX = 96
        private const val MAPS_PACKAGE = "com.google.android.apps.maps"
    }
}
