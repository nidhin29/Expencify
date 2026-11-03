package com.example.expencify

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/** Wire-compatible with SPENDY02 in backup_crypto.dart. No files or logging. */
object BackupCrypto {
    private val magic = "SPENDY02".toByteArray(Charsets.US_ASCII)
    private const val limit = 50 * 1024 * 1024
    private fun derive(password: String, salt: ByteArray): ByteArray {
        val chars = password.toCharArray()
        val spec = PBEKeySpec(chars, salt, 600000, 256)
        chars.fill('\u0000')
        return try { SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded }
        finally { spec.clearPassword() }
    }
    fun encrypt(data: ByteArray, password: String): ByteArray {
        require(data.size <= limit)
        val random = SecureRandom()
        val salt = ByteArray(16).also { random.nextBytes(it) }
        val nonce = ByteArray(12).also { random.nextBytes(it) }
        val header = magic + salt + nonce
        val key = derive(password, salt)
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
            cipher.updateAAD(header)
            val output = ByteArray(header.size + cipher.getOutputSize(data.size))
            header.copyInto(output)
            cipher.doFinal(data, 0, data.size, output, header.size)
            output
        } finally { key.fill(0) }
    }
    fun decrypt(data: ByteArray, password: String): ByteArray {
        require(data.size in 52..(limit + 1024) && data.copyOfRange(0, 8).contentEquals(magic))
        val key = derive(password, data.copyOfRange(8, 24))
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, data.copyOfRange(24, 36)))
            cipher.updateAAD(data.copyOfRange(0, 36))
            val output = ByteArray(data.size - 52)
            try {
                cipher.doFinal(data, 36, data.size - 36, output, 0)
                output
            } catch (error: Exception) { output.fill(0); throw error }
        } finally { key.fill(0) }
    }
}
