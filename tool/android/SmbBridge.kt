package com.luchorcompartidos.diskcompare

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.hierynomus.mssmb2.SMBApiException
import com.hierynomus.security.bc.BCSecurityProvider
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.share.DiskShare
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Lectura (solo lectura) de una carpeta compartida de Windows por SMB 2/3, con smbj.
 * Canal "dc/smb":
 *  - list  {host, share, path, user, password, domain} → nombres de subcarpetas
 *  - scan  {...} → recorre todo y escribe filesDir/pc-scan.tsv (ruta\ttamaño\tfecha);
 *                  avisa el avance con invokeMethod("progress")
 *  - cancel → corta el scan en curso
 * Nunca crea, modifica ni borra nada en la PC.
 */
class SmbBridge(private val ctx: Context, private val ch: MethodChannel) {
    private val exec = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)

    private class Cancelled : Exception("Cancelado")

    fun cancel() = cancelled.set(true)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cancel" -> {
                cancel()
                result.success(true)
            }
            "list" -> run(result) { withShare(call) { share, base -> listDirs(share, base) } }
            "scan" -> {
                cancelled.set(false)
                run(result) { withShare(call) { share, base -> scan(share, base) } }
            }
            else -> result.notImplemented()
        }
    }

    private fun run(result: MethodChannel.Result, work: () -> Any?) {
        exec.execute {
            try {
                val r = work()
                main.post { result.success(r) }
            } catch (e: Throwable) {
                val (code, msg) = describe(e)
                main.post { result.error(code, msg, null) }
            }
        }
    }

    private fun <T> withShare(call: MethodCall, block: (DiskShare, String) -> T): T {
        val host = (call.argument<String>("host") ?: "").trim()
        val shareName = (call.argument<String>("share") ?: "").trim()
        val path = (call.argument<String>("path") ?: "").replace('/', '\\').trim('\\')
        val user = call.argument<String>("user") ?: ""
        val pass = call.argument<String>("password") ?: ""
        val domain = call.argument<String>("domain") ?: ""
        if (host.isEmpty() || shareName.isEmpty()) throw IllegalArgumentException("Falta la PC o la carpeta compartida")

        val config = SmbConfig.builder()
            .withSecurityProvider(BCSecurityProvider())
            .withTimeout(30, TimeUnit.SECONDS)
            .withSoTimeout(60, TimeUnit.SECONDS)
            .build()
        return SMBClient(config).use { client ->
            val conn = try {
                client.connect(host)
            } catch (e: Exception) {
                // Sin punto en el nombre: probar también "NOMBRE.local" (mDNS de Windows 10/11)
                if (host.contains('.') || host.contains(':')) throw e
                client.connect("$host.local")
            }
            conn.use {
                val auth = if (user.isBlank()) AuthenticationContext.guest()
                else AuthenticationContext(user, pass.toCharArray(), domain.ifBlank { null })
                val session = conn.authenticate(auth)
                session.use {
                    val share = session.connectShare(shareName) as? DiskShare
                        ?: throw IllegalArgumentException("\"$shareName\" no es una carpeta compartida de archivos")
                    share.use { block(share, path) }
                }
            }
        }
    }

    private fun isDir(attrs: Long) = (attrs and 0x10L) != 0L
    private fun isLink(attrs: Long) = (attrs and 0x400L) != 0L // junction/enlace: no se recorre

    private fun listDirs(share: DiskShare, base: String): List<String> =
        share.list(base)
            .filter { it.fileName != "." && it.fileName != ".." && isDir(it.fileAttributes) && !isLink(it.fileAttributes) }
            .map { it.fileName }
            .sortedBy { it.lowercase() }

    private fun scan(share: DiskShare, base: String): Map<String, Any> {
        val out = File(ctx.filesDir, "pc-scan.tsv")
        val tmp = File(ctx.filesDir, "pc-scan.tmp")
        var files = 0L
        var bytes = 0L
        var denied = 0
        var lastSent = 0L
        tmp.bufferedWriter(Charsets.UTF_8).use { w ->
            val stack = java.util.ArrayDeque<String>()
            stack.push("")
            while (!stack.isEmpty()) {
                if (cancelled.get()) throw Cancelled()
                val rel = stack.pop()
                val full = when {
                    rel.isEmpty() -> base
                    base.isEmpty() -> rel
                    else -> "$base\\$rel"
                }
                val list = try {
                    share.list(full)
                } catch (e: SMBApiException) {
                    // Carpeta sin permiso: se anota y se sigue
                    w.write("!\t" + rel.replace('\\', '/') + "\n")
                    denied++
                    continue
                }
                for (f in list) {
                    val n = f.fileName
                    if (n == "." || n == "..") continue
                    val childRel = if (rel.isEmpty()) n else "$rel\\$n"
                    val attrs = f.fileAttributes
                    if (isDir(attrs)) {
                        if (!isLink(attrs)) stack.push(childRel)
                        continue
                    }
                    val size = f.endOfFile
                    val mt = try { f.lastWriteTime.toEpochMillis() } catch (e: Exception) { 0L }
                    w.write(childRel.replace('\\', '/'))
                    w.write("\t$size\t$mt\n")
                    files++
                    bytes += size
                }
                val now = System.currentTimeMillis()
                if (now - lastSent > 400) {
                    lastSent = now
                    val f = files
                    val b = bytes
                    val c = rel.replace('\\', '/')
                    main.post { ch.invokeMethod("progress", mapOf("files" to f, "bytes" to b, "current" to c)) }
                }
            }
        }
        if (out.exists()) out.delete()
        if (!tmp.renameTo(out)) {
            tmp.copyTo(out, overwrite = true)
            tmp.delete()
        }
        return mapOf("path" to out.absolutePath, "files" to files, "bytes" to bytes, "denied" to denied)
    }

    /** Traduce el error a un código y un mensaje en castellano. */
    private fun describe(e: Throwable): Pair<String, String> {
        var t: Throwable? = e
        var depth = 0
        while (t != null && depth < 10) {
            when (t) {
                is Cancelled -> return "cancel" to "Cancelado"
                is UnknownHostException ->
                    return "host" to "No se encontró la PC. Probá escribir su dirección IP (por ejemplo \\\\192.168.0.10\\Carpeta)."
                is ConnectException, is NoRouteToHostException, is SocketTimeoutException ->
                    return "net" to "No se pudo conectar con la PC. Revisá que esté prendida, en la misma red WiFi y con la carpeta compartida."
                is SMBApiException -> {
                    val st = try { t.status.name } catch (x: Exception) { "" }
                    return when (st) {
                        "STATUS_LOGON_FAILURE", "STATUS_WRONG_PASSWORD", "STATUS_NO_SUCH_USER" ->
                            "auth" to "Usuario o contraseña incorrectos (son los de Windows en esa PC)."
                        "STATUS_ACCOUNT_DISABLED", "STATUS_ACCOUNT_RESTRICTION" ->
                            "auth" to "Windows no deja entrar con ese usuario (cuenta deshabilitada o sin contraseña)."
                        "STATUS_ACCESS_DENIED" ->
                            "denied" to "Acceso denegado: ese usuario no tiene permiso sobre la carpeta compartida."
                        "STATUS_BAD_NETWORK_NAME" ->
                            "share" to "No existe esa carpeta compartida en la PC. Revisá el nombre con el que la compartiste."
                        "STATUS_OBJECT_NAME_NOT_FOUND", "STATUS_OBJECT_PATH_NOT_FOUND" ->
                            "path" to "No existe esa subcarpeta dentro de la carpeta compartida."
                        else -> "smb" to "La PC respondió con un error ($st)."
                    }
                }
                is IllegalArgumentException -> return "args" to (t.message ?: "Datos incompletos")
            }
            t = t.cause
            depth++
        }
        return "error" to (e.message ?: e.toString())
    }
}
