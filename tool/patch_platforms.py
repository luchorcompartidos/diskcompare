"""Ajustes a la carpeta android/ que genera `flutter create` en GitHub Actions.

Uso: python3 tool/patch_platforms.py android|signing
"""
import glob
import re
import sys

MAIN_ACTIVITY = """package com.luchorcompartidos.diskcompare

import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dc/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdk" -> result.success(Build.VERSION.SDK_INT)
                    "volumes" -> result.success(volumes())
                    else -> result.notImplemented()
                }
            }
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
"""

SIGNING = """

// Firma fija (la clave llega desde los Secrets del repo)
System.getenv("DC_KEYSTORE_PATH")?.let { ks ->
    android {
        signingConfigs {
            create("dc") {
                storeFile = file(ks)
                storePassword = System.getenv("DC_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("DC_KEY_ALIAS")
                keyPassword = System.getenv("DC_KEYSTORE_PASSWORD")
            }
        }
        buildTypes {
            getByName("release") { signingConfig = signingConfigs.getByName("dc") }
        }
    }
}
"""


def patch(path, old, new):
    s = open(path, encoding="utf-8").read()
    if new in s:
        return
    if old not in s:
        sys.exit(f"::error::No encontré el punto a modificar en {path}: {old!r}")
    open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))
    print(f"OK {path}")


def android():
    m = "android/app/src/main/AndroidManifest.xml"
    s = open(m, encoding="utf-8").read()
    s = re.sub(r'android:label="[^"]*"', 'android:label="DiskCompare"', s, count=1)
    open(m, "w", encoding="utf-8").write(s)
    if "MANAGE_EXTERNAL_STORAGE" not in s:
        patch(m, "<application",
              '<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />\n'
              '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\n'
              '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />\n'
              '    <application')
    s = open(m, encoding="utf-8").read()
    if "requestLegacyExternalStorage" not in s:
        patch(m, "<application", '<application android:requestLegacyExternalStorage="true"')
    found = False
    for ma in glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True):
        open(ma, "w", encoding="utf-8").write(MAIN_ACTIVITY)
        print(f"OK {ma}")
        found = True
    if not found:
        sys.exit("::error::No encontré MainActivity.kt")


def signing():
    g = "android/app/build.gradle.kts"
    s = open(g, encoding="utf-8").read()
    if "DC_KEYSTORE_PATH" not in s:
        open(g, "a", encoding="utf-8").write(SIGNING)
        print(f"OK {g}")


if __name__ == "__main__":
    {"android": android, "signing": signing}[sys.argv[1]]()
