package com.sbjglitch.thaal

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.system.ErrnoException
import android.system.OsConstants
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

// flutter_readium's reader view requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    private var pendingSave: PendingSave? = null

    // Registered at construction, as the Activity Result API requires.
    private val createDocument =
        registerForActivityResult(
            ActivityResultContracts.CreateDocument(BACKUP_MIME_TYPE),
        ) { uri -> onDocumentCreated(uri) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL)
            .setMethodCallHandler(::onBackupCall)
    }

    private fun onBackupCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveBackup") {
            result.notImplemented()
            return
        }
        val sourcePath = call.argument<String>("sourcePath")
        val suggestedName = call.argument<String>("suggestedName")
        if (sourcePath == null || suggestedName == null) {
            result.error("bad_arguments", null, null)
            return
        }
        if (pendingSave != null) {
            result.error("busy", null, null)
            return
        }
        pendingSave = PendingSave(File(sourcePath), suggestedName, result)
        createDocument.launch(suggestedName)
    }

    private fun onDocumentCreated(uri: Uri?) {
        val save = pendingSave ?: return
        pendingSave = null
        if (uri == null) {
            save.result.success(null)
            return
        }
        // Copy off the main thread; backups can be large.
        io.execute {
            val outcome =
                try {
                    copyTo(save.source, uri)
                    Result.success(displayName(uri) ?: save.suggestedName)
                } catch (error: IOException) {
                    deletePartial(uri)
                    Result.failure(error)
                } catch (error: SecurityException) {
                    deletePartial(uri)
                    Result.failure(error)
                }
            mainHandler.post {
                outcome.fold(
                    onSuccess = { name -> save.result.success(name) },
                    onFailure = { error ->
                        val code = if (isOutOfSpace(error)) "no_space" else "write_failed"
                        // No message: it could contain the document location.
                        save.result.error(code, null, null)
                    },
                )
            }
        }
    }

    private fun copyTo(source: File, uri: Uri) {
        val output =
            contentResolver.openOutputStream(uri, "wt")
                ?: throw IOException("no output stream")
        output.use { out ->
            source.inputStream().use { input -> input.copyTo(out, COPY_BUFFER_BYTES) }
            out.flush()
        }
    }

    private fun displayName(uri: Uri): String? =
        try {
            contentResolver
                .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        } catch (_: RuntimeException) {
            null
        }

    // Removes the incomplete document so a failed save leaves nothing behind.
    private fun deletePartial(uri: Uri) {
        try {
            DocumentsContract.deleteDocument(contentResolver, uri)
        } catch (_: Exception) {
            // Not every provider allows deletion; nothing more can be done.
        }
    }

    private fun isOutOfSpace(error: Throwable): Boolean {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is ErrnoException && cause.errno == OsConstants.ENOSPC) return true
            if (cause.message?.contains("ENOSPC") == true) return true
            cause = cause.cause
        }
        return false
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    private class PendingSave(
        val source: File,
        val suggestedName: String,
        val result: MethodChannel.Result,
    )

    private companion object {
        const val BACKUP_CHANNEL = "com.sbjglitch.thaal/backup"

        // A specific type such as application/zip makes some providers
        // append their own extension; octet-stream keeps ".readerbackup".
        const val BACKUP_MIME_TYPE = "application/octet-stream"
        const val COPY_BUFFER_BYTES = 1 shl 20
    }
}
