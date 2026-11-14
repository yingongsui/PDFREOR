package com.yin.pdfreor

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity(), InputManager.InputDeviceListener {
    private val STYLUS_CHANNEL = "com.yin.pdfreor/stylus"
    private val INTENT_CHANNEL = "com.yin.pdfreor/intent"
    private val MAX_CLIPBOARD_IMAGE_BYTES = 24 * 1024 * 1024
    private val MAX_EXTERNAL_PDF_CACHE_FILES = 20

    private var stylusChannel: MethodChannel? = null
    private var intentChannel: MethodChannel? = null
    private var inputManager: InputManager? = null
    private var stylusNotified = false
    @Volatile
    private var pendingPdfPath: String? = null
    @Volatile
    private var initialPdfConsumed = false
    private val bgExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
        handleIncomingIntent(intent, notifyLive = false)
    }

    override fun onResume() {
        super.onResume()
        requestHighRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            requestHighRefreshRate()
        }
    }

    private fun requestHighRefreshRate() {
        try {
            val currentDisplay = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return

            val supportedModes = currentDisplay.supportedModes
            if (supportedModes.isEmpty()) return

            val activeMode = currentDisplay.mode
            val bestMode = supportedModes
                .filter {
                    it.physicalWidth == activeMode.physicalWidth &&
                        it.physicalHeight == activeMode.physicalHeight
                }
                .maxByOrNull { it.refreshRate }
                ?: supportedModes.maxByOrNull { it.refreshRate }
                ?: return

            val params = window.attributes
            if (params.preferredDisplayModeId != bestMode.modeId ||
                params.preferredRefreshRate != bestMode.refreshRate
            ) {
                params.preferredDisplayModeId = bestMode.modeId
                params.preferredRefreshRate = bestMode.refreshRate
                window.attributes = params
            }

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R &&
                bestMode.refreshRate > 60.5f
            ) {
                applySurfaceFrameRate(window?.decorView, bestMode.refreshRate)
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "Unable to request high refresh rate: $e")
        }
    }

    private fun applySurfaceFrameRate(view: View?, frameRate: Float) {
        if (view == null || android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) return
        if (view is SurfaceView) {
            val surface = view.holder.surface
            if (surface != null && surface.isValid) {
                try {
                    surface.setFrameRate(frameRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
                } catch (_: Exception) {}
            }
        } else if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                applySurfaceFrameRate(view.getChildAt(i), frameRate)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent, notifyLive = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        stylusNotified = false

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STYLUS_CHANNEL)
        stylusChannel = channel

        val iChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL)
        intentChannel = iChannel

        iChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialPdfPath" -> {
                    initialPdfConsumed = true
                    val path = pendingPdfPath
                    pendingPdfPath = null
                    result.success(path)
                }
                else -> result.notImplemented()
            }
        }

        inputManager = getSystemService(Context.INPUT_SERVICE) as? InputManager
        inputManager?.registerInputDeviceListener(this, null)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isStylusConnected" -> {
                    val connected = stylusNotified || isStylusConnected()
                    if (connected) stylusNotified = true
                    result.success(connected)
                }
                "getClipboardImage" -> {
                    try {
                        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        val clip = clipboard.primaryClip
                        var imageUri: Uri? = null
                        var imageMime: String? = null
                        if (clip != null && clip.itemCount > 0) {
                            for (i in 0 until clip.itemCount) {
                                val item = clip.getItemAt(i)
                                val uri = item.uri
                                if (uri != null) {
                                    val mime = contentResolver.getType(uri)
                                    if (mime == null || mime.startsWith("image/")) {
                                        imageUri = uri
                                        imageMime = mime
                                        break
                                    }
                                }
                            }
                        }
                        if (imageUri == null) {
                            result.success(null)
                        } else {
                            val targetUri = imageUri
                            val targetMime = imageMime
                            bgExecutor.execute {
                                var compacted: ByteArray? = null
                                try {
                                    val raw = readStreamBounded(targetUri, MAX_CLIPBOARD_IMAGE_BYTES)
                                    if (raw != null && raw.isNotEmpty()) {
                                        compacted = compactClipboardImageBytes(raw, targetMime)
                                    }
                                } catch (e: Exception) {
                                    Log.e("PdfReorClipboard", "Error reading clipboard image: $e")
                                }
                                runOnUiThread {
                                    result.success(compacted)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("PdfReorClipboard", "Error reading clipboard image: $e")
                        result.success(null)
                    }
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            startActivity(browserIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error opening URL: $e")
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "getStorageVolumes" -> {
                    try {
                        val list = mutableListOf<String>()
                        val sm = getSystemService(Context.STORAGE_SERVICE) as? android.os.storage.StorageManager
                        if (sm != null) {
                            for (vol in sm.storageVolumes) {
                                val state = vol.state
                                if (state == Environment.MEDIA_MOUNTED || state == Environment.MEDIA_MOUNTED_READ_ONLY) {
                                    var path: String? = null
                                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                        val dir = vol.directory
                                        if (dir != null) {
                                            path = dir.absolutePath
                                        }
                                    }
                                    if (path == null) {
                                        try {
                                            val getPath = vol.javaClass.getMethod("getPath")
                                            path = getPath.invoke(vol) as? String
                                        } catch (_: Exception) {}
                                    }
                                    if (path != null && path.isNotBlank() && !list.contains(path)) {
                                        list.add(path)
                                    }
                                }
                            }
                        }

                        try {
                            val extDirs = getExternalFilesDirs(null)
                            if (extDirs != null) {
                                for (extFile in extDirs) {
                                    if (extFile != null) {
                                        val absPath = extFile.absolutePath
                                        val idx = absPath.indexOf("/Android/")
                                        if (idx != -1) {
                                            val root = absPath.substring(0, idx)
                                            if (root.isNotBlank() && !list.contains(root)) {
                                                list.add(root)
                                            }
                                        }
                                    }
                                }
                            }
                        } catch (_: Exception) {}

                        if (list.isEmpty()) {
                            list.add(Environment.getExternalStorageDirectory().absolutePath)
                        }
                        result.success(list)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error getting storage volumes: $e")
                        result.success(listOf("/storage/emulated/0"))
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun readStreamBounded(uri: Uri, maxBytes: Int): ByteArray? {
        contentResolver.openInputStream(uri)?.use { input ->
            val out = ByteArrayOutputStream()
            val buf = ByteArray(16 * 1024)
            var total = 0
            while (true) {
                val read = input.read(buf)
                if (read <= 0) break
                total += read
                if (total > maxBytes) {
                    Log.w("PdfReorClipboard", "Clipboard image exceeds $maxBytes bytes limit")
                    return null
                }
                out.write(buf, 0, read)
            }
            return out.toByteArray()
        }
        return null
    }

    private fun compactClipboardImageBytes(bytes: ByteArray, mime: String?): ByteArray {
        var decoded: Bitmap? = null
        var scaled: Bitmap? = null
        try {
            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, boundsOpts)
            val origW = boundsOpts.outWidth
            val origH = boundsOpts.outHeight
            if (origW <= 0 || origH <= 0) return bytes

            val maxSide = max(origW, origH)
            if (maxSide <= 2048 && bytes.size <= 120 * 1024) {
                return bytes
            }

            var sampleSize = 1
            while ((maxSide / (sampleSize * 2)) >= 2048) {
                sampleSize *= 2
            }

            val decodeOpts = BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOpts) ?: return bytes

            val curMax = max(decoded.width, decoded.height)
            val targetBmp: Bitmap = if (curMax > 2048) {
                val ratio = 2048.0 / curMax.toDouble()
                val newW = max(1, (decoded.width * ratio).roundToInt())
                val newH = max(1, (decoded.height * ratio).roundToInt())
                val s = Bitmap.createScaledBitmap(decoded, newW, newH, true)
                if (s !== decoded) {
                    scaled = s
                }
                s
            } else {
                decoded
            }

            val isKnownJpeg = mime.equals("image/jpeg", ignoreCase = true) ||
                mime.equals("image/jpg", ignoreCase = true)
            var isFullyOpaque = isKnownJpeg || !targetBmp.hasAlpha()

            if (!isFullyOpaque) {
                isFullyOpaque = true
                val rowPixels = IntArray(targetBmp.width)
                for (y in 0 until targetBmp.height) {
                    targetBmp.getPixels(rowPixels, 0, targetBmp.width, 0, y, targetBmp.width, 1)
                    for (px in rowPixels) {
                        if ((px ushr 24) < 252) {
                            isFullyOpaque = false
                            break
                        }
                    }
                    if (!isFullyOpaque) break
                }
            }

            val out = ByteArrayOutputStream()
            if (isFullyOpaque) {
                if (targetBmp.compress(Bitmap.CompressFormat.JPEG, 86, out)) {
                    val jpegBytes = out.toByteArray()
                    if (jpegBytes.isNotEmpty() &&
                        (maxSide > 2048 || jpegBytes.size < (bytes.size * 85) / 100)
                    ) {
                        return if (jpegBytes.size < bytes.size) jpegBytes else bytes
                    }
                }
            } else if (maxSide > 2048) {
                if (targetBmp.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                    val pngBytes = out.toByteArray()
                    if (pngBytes.isNotEmpty() && pngBytes.size < bytes.size) {
                        return pngBytes
                    }
                }
            }
        } catch (e: Exception) {
            Log.w("PdfReorClipboard", "Clipboard image compaction skipped: $e")
        } finally {
            try {
                scaled?.recycle()
            } catch (_: Exception) {}
            try {
                decoded?.recycle()
            } catch (_: Exception) {}
        }
        return bytes
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        inputManager?.unregisterInputDeviceListener(this)
        stylusChannel?.setMethodCallHandler(null)
        intentChannel?.setMethodCallHandler(null)
        stylusChannel = null
        intentChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleIncomingIntent(incoming: Intent?, notifyLive: Boolean) {
        if (incoming == null) return
        if (incoming.action != Intent.ACTION_VIEW) return
        val uri = incoming.data ?: return

        bgExecutor.execute {
            val resolvedPath = resolvePdfUriToPath(uri) ?: return@execute
            runOnUiThread {
                if ((notifyLive || initialPdfConsumed) && intentChannel != null) {
                    intentChannel?.invokeMethod("onOpenExternalPdf", resolvedPath)
                } else {
                    pendingPdfPath = resolvedPath
                }
            }
        }
    }

    private fun shortUriHash(raw: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray(Charsets.UTF_8))
        return digest.take(6).joinToString("") { "%02x".format(it) }
    }

    private fun pruneExternalPdfCache(importDir: File) {
        try {
            val files = importDir.listFiles()?.filter { it.isFile } ?: return
            if (files.size <= MAX_EXTERNAL_PDF_CACHE_FILES) return
            val sorted = files.sortedBy { it.lastModified() }
            val deleteCount = sorted.size - MAX_EXTERNAL_PDF_CACHE_FILES
            for (i in 0 until deleteCount) {
                sorted[i].delete()
            }
        } catch (_: Exception) {}
    }

    private fun resolvePdfUriToPath(uri: Uri): String? {
        try {
            if (uri.scheme == "file") {
                val p = uri.path
                if (!p.isNullOrBlank() && File(p).exists()) {
                    return p
                }
            }

            // Attempt direct storage path resolution for externalstorage DocumentsProvider
            if (uri.scheme == "content" && DocumentsContract.isDocumentUri(this, uri)) {
                if (uri.authority == "com.android.externalstorage.documents") {
                    val docId = DocumentsContract.getDocumentId(uri)
                    val split = docId.split(":")
                    if (split.size >= 2) {
                        val type = split[0]
                        val relPath = split.subList(1, split.size).joinToString(":")
                        val candidate = if (type.equals("primary", ignoreCase = true)) {
                            "${Environment.getExternalStorageDirectory().absolutePath}/$relPath"
                        } else {
                            "/storage/$type/$relPath"
                        }
                        val f = File(candidate)
                        if (f.exists() && f.canRead()) {
                            return f.absolutePath
                        }
                    }
                }
            }

            // Fallback: copy content:// stream to app cache while preserving display filename
            if (uri.scheme == "content") {
                var displayName: String? = null
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0) {
                            displayName = cursor.getString(idx)
                        }
                    }
                }
                var safeName = (displayName ?: uri.lastPathSegment ?: "document.pdf")
                    .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                    .trim()
                if (safeName.isEmpty()) safeName = "document.pdf"
                if (!safeName.lowercase().endsWith(".pdf")) {
                    safeName = "$safeName.pdf"
                }

                val importDir = File(cacheDir, "external_pdfs")
                if (!importDir.exists()) {
                    importDir.mkdirs()
                }
                val uniqueName = "${shortUriHash(uri.toString())}_$safeName"
                val destFile = File(importDir, uniqueName)
                val tempFile = File(importDir, "$uniqueName.tmp")
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(tempFile).use { output ->
                        input.copyTo(output)
                        output.fd.sync()
                    }
                }
                if (tempFile.exists() && tempFile.length() > 0L) {
                    if (destFile.exists()) {
                        destFile.delete()
                    }
                    if (!tempFile.renameTo(destFile)) {
                        tempFile.copyTo(destFile, overwrite = true)
                        tempFile.delete()
                    }
                    pruneExternalPdfCache(importDir)
                    return destFile.absolutePath
                } else {
                    tempFile.delete()
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error resolving external PDF URI: $e")
        }
        return null
    }

    override fun onDestroy() {
        inputManager?.unregisterInputDeviceListener(this)
        bgExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun isStylusConnected(): Boolean {
        val im = inputManager ?: return false
        for (id in im.inputDeviceIds) {
            val device = im.getInputDevice(id)
            if (device != null && (device.sources and InputDevice.SOURCE_STYLUS) == InputDevice.SOURCE_STYLUS) {
                return true
            }
        }
        return false
    }

    private fun checkAndNotifyStylus() {
        if (stylusNotified) return
        stylusNotified = true
        runOnUiThread {
            stylusChannel?.invokeMethod("onStylusConnected", true)
        }
    }

    override fun onInputDeviceAdded(deviceId: Int) {
        if (isStylusConnected()) {
            checkAndNotifyStylus()
        }
    }

    override fun onInputDeviceChanged(deviceId: Int) {
        if (isStylusConnected()) {
            checkAndNotifyStylus()
        }
    }

    override fun onInputDeviceRemoved(deviceId: Int) {
        if (!isStylusConnected()) {
            stylusNotified = false
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (!stylusNotified) {
            val toolType = event.getToolType(0)
            if (toolType == MotionEvent.TOOL_TYPE_STYLUS || toolType == MotionEvent.TOOL_TYPE_ERASER) {
                checkAndNotifyStylus()
            }
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (!stylusNotified) {
            val toolType = event.getToolType(0)
            if (toolType == MotionEvent.TOOL_TYPE_STYLUS || toolType == MotionEvent.TOOL_TYPE_ERASER) {
                checkAndNotifyStylus()
            }
        }
        return super.dispatchTouchEvent(event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        val isLenovoPenKey = keyCode in 600..604 || keyCode == 289 || keyCode == 290 ||
                keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_PRIMARY ||
                keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_SECONDARY ||
                keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_TERTIARY ||
                keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_TAIL

        if (isLenovoPenKey) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                if (event.repeatCount == 0) {
                    stylusChannel?.invokeMethod("onStylusButtonDown", null)
                }
            } else if (event.action == KeyEvent.ACTION_UP) {
                stylusChannel?.invokeMethod("onStylusButtonUp", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
