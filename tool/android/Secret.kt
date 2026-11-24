package com.luchorcompartidos.diskcompare

import android.annotation.TargetApi
import android.content.Context
import android.os.Build
import android.security.KeyPairGeneratorSpec
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.util.Calendar
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.security.auth.x500.X500Principal

/**
 * Guarda textos cifrados (la contraseña de la PC) con una clave del Android Keystore,
 * que no sale del equipo.
 *  - Android 6 o más: AES-GCM.
 *  - Android 5 (sin AES en el Keystore): RSA.
 * Si la clave se pierde (por ejemplo, al cambiar el bloqueo de pantalla en Android 5),
 * load() devuelve null y la app vuelve a pedir la contraseña.
 */
object Secret {
    private const val PREFS = "dc_secret"
    private const val AES_ALIAS = "dc_secret_aes"
    private const val RSA_ALIAS = "dc_secret_rsa"

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun save(ctx: Context, key: String, value: String) {
        val data = value.toByteArray(Charsets.UTF_8)
        val enc = if (Build.VERSION.SDK_INT >= 23) {
            aesEncrypt(data)
        } else {
            val entry = rsaEntry(ctx)
            val c = rsaCipher()
            c.init(Cipher.ENCRYPT_MODE, entry.certificate.publicKey)
            "r:" + b64(c.doFinal(data))
        }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(key, enc).apply()
    }

    fun load(ctx: Context, key: String): String? {
        val s = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(key, null) ?: return null
        return try {
            val parts = s.split(":")
            when (parts[0]) {
                "a" -> if (Build.VERSION.SDK_INT >= 23) aesDecrypt(parts[1], parts[2]) else null
                "r" -> {
                    val c = rsaCipher()
                    c.init(Cipher.DECRYPT_MODE, rsaEntry(ctx).privateKey)
                    String(c.doFinal(unb64(parts[1])), Charsets.UTF_8)
                }
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }

    fun delete(ctx: Context, key: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(key).apply()
    }

    @TargetApi(23)
    private fun aesEncrypt(data: ByteArray): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, aesKey())
        return "a:" + b64(c.iv) + ":" + b64(c.doFinal(data))
    }

    @TargetApi(23)
    private fun aesDecrypt(iv: String, data: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, aesKey(), GCMParameterSpec(128, unb64(iv)))
        return String(c.doFinal(unb64(data)), Charsets.UTF_8)
    }

    @TargetApi(23)
    private fun aesKey(): SecretKey {
        val ks = keyStore()
        (ks.getKey(AES_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(AES_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return gen.generateKey()
    }

    @Suppress("DEPRECATION")
    private fun rsaEntry(ctx: Context): KeyStore.PrivateKeyEntry {
        val ks = keyStore()
        if (!ks.containsAlias(RSA_ALIAS)) {
            val start = Calendar.getInstance()
            val end = Calendar.getInstance().apply { add(Calendar.YEAR, 30) }
            val spec = KeyPairGeneratorSpec.Builder(ctx)
                .setAlias(RSA_ALIAS)
                .setSubject(X500Principal("CN=DiskCompare"))
                .setSerialNumber(BigInteger.ONE)
                .setStartDate(start.time)
                .setEndDate(end.time)
                .build()
            val gen = KeyPairGenerator.getInstance("RSA", "AndroidKeyStore")
            gen.initialize(spec)
            gen.generateKeyPair()
        }
        return ks.getEntry(RSA_ALIAS, null) as KeyStore.PrivateKeyEntry
    }

    private fun rsaCipher(): Cipher = try {
        Cipher.getInstance("RSA/ECB/PKCS1Padding", "AndroidOpenSSL")
    } catch (e: Exception) {
        Cipher.getInstance("RSA/ECB/PKCS1Padding")
    }

    private fun b64(b: ByteArray): String = Base64.encodeToString(b, Base64.NO_WRAP)
    private fun unb64(s: String): ByteArray = Base64.decode(s, Base64.NO_WRAP)
}
