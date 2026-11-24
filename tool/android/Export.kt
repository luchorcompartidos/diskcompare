package com.luchorcompartidos.diskcompare

import android.app.Activity
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File

// Archivo copiado por tool/patch_platforms.py. Exportar CSV sin plugins (sirve desde Android 5):
// - Guardar: Android 10+ con MediaStore (Descargas/DiskCompare); Android 5 a 9 escribiendo
//   en la carpeta pública Descargas (permiso de archivos de la app).
// - Compartir: FileProvider (autoridad <paquete>.files, carpeta cache/export) + menú de Android.
object Export {
    private const val FOLDER = "DiskCompare"
    private const val MIME = "text/csv"

    /** Copia [src] a Descargas/DiskCompare/[name]. Devuelve la ruta para mostrar. */
    fun saveToDownloads(a: Activity, src: String, name: String): String {
        val f = File(src)
        if (Build.VERSION.SDK_INT >= 29) {
            val r = a.contentResolver
            val v = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, MIME)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + FOLDER)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = r.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v)
                ?: throw Exception("No se pudo crear el archivo en Descargas")
            try {
                val out = r.openOutputStream(uri) ?: throw Exception("No se pudo escribir en Descargas")
                out.use { o -> f.inputStream().use { it.copyTo(o) } }
                val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                r.update(uri, done, null, null)
            } catch (e: Exception) {
                try { r.delete(uri, null, null) } catch (x: Exception) {}
                throw e
            }
            var shown = name // Android puede agregar " (1)" si ya existe
            try {
                r.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) shown = c.getString(0) ?: name
                }
            } catch (e: Exception) {}
            return "Descargas/$FOLDER/$shown"
        }
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), FOLDER)
        if (!dir.isDirectory && !dir.mkdirs()) {
            throw Exception("No se pudo crear Descargas/$FOLDER. Revisá que la app tenga el permiso de archivos.")
        }
        val out = File(dir, name)
        f.copyTo(out, overwrite = true)
        try {
            MediaScannerConnection.scanFile(a, arrayOf(out.absolutePath), arrayOf(MIME), null)
        } catch (e: Exception) {}
        return "Descargas/$FOLDER/$name"
    }

    /** Abre el menú "Compartir" de Android con el archivo [src]. */
    fun share(a: Activity, src: String, title: String) {
        val uri = FileProvider.getUriForFile(a, a.packageName + ".files", File(src))
        val send = Intent(Intent.ACTION_SEND).apply {
            type = MIME
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, title)
            clipData = ClipData.newRawUri(title, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        a.startActivity(Intent.createChooser(send, "Compartir CSV"))
    }
}
