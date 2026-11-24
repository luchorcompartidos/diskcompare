package com.luchorcompartidos.diskcompare

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Archivo copiado por tool/patch_platforms.py a la carpeta android/ que genera `flutter create`.
class MainActivity : FlutterActivity() {
    private var smb: SmbBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "dc/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "sdk" -> result.success(Build.VERSION.SDK_INT)
                "volumes" -> result.success(volumes())
                "filesDir" -> result.success(filesDir.absolutePath)
                "openUrl" -> try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url") ?: ""))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("url", e.message ?: e.toString(), null)
                }
                "secretSave" -> try {
                    Secret.save(this, call.argument<String>("key") ?: "", call.argument<String>("value") ?: "")
                    result.success(true)
                } catch (e: Exception) {
                    result.error("secret", e.message ?: e.toString(), null)
                }
                "secretLoad" -> result.success(Secret.load(this, call.argument<String>("key") ?: ""))
                "secretDelete" -> {
                    Secret.delete(this, call.argument<String>("key") ?: "")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val smbChannel = MethodChannel(messenger, "dc/smb")
        val bridge = SmbBridge(this, smbChannel)
        smb = bridge
        smbChannel.setMethodCallHandler { call, result -> bridge.handle(call, result) }
    }

    override fun onDestroy() {
        smb?.cancel()
        super.onDestroy()
    }

    /** Almacenamiento interno y tarjetas SD, con su espacio total y libre. */
    private fun volumes(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        for (d in getExternalFilesDirs(null)) {
            if (d == null) continue
            val p = d.absolutePath
            val i = p.indexOf("/Android/")
            if (i <= 0) continue
            val root = File(p.substring(0, i))
            try {
                val st = StatFs(root.path)
                val removable = try { Environment.isExternalStorageRemovable(d) } catch (e: Exception) { false }
                out.add(mapOf(
                    "path" to root.path,
                    "label" to (if (removable) "Tarjeta SD" else "Almacenamiento interno"),
                    "total" to st.totalBytes,
                    "free" to st.availableBytes,
                    "removable" to removable,
                ))
            } catch (e: Exception) {
            }
        }
        return out
    }
}
