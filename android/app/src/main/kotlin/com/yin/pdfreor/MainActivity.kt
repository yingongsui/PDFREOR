package com.yin.pdfreor

import android.content.Context
import android.hardware.input.InputManager
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), InputManager.InputDeviceListener {
    private val STYLUS_CHANNEL = "com.yin.pdfreor/stylus"
    private var stylusChannel: MethodChannel? = null
    private var inputManager: InputManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STYLUS_CHANNEL)
        stylusChannel = channel

        inputManager = getSystemService(Context.INPUT_SERVICE) as? InputManager
        inputManager?.registerInputDeviceListener(this, null)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isStylusConnected" -> {
                    result.success(isStylusConnected())
                }
                "getClipboardImage" -> {
                    try {
                        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        val clip = clipboard.primaryClip
                        if (clip != null && clip.itemCount > 0) {
                            for (i in 0 until clip.itemCount) {
                                val item = clip.getItemAt(i)
                                val uri = item.uri
                                if (uri != null) {
                                    val stream = contentResolver.openInputStream(uri)
                                    val bytes = stream?.readBytes()
                                    stream?.close()
                                    if (bytes != null && bytes.isNotEmpty()) {
                                        result.success(bytes)
                                        return@setMethodCallHandler
                                    }
                                }
                            }
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("PdfReorClipboard", "Error reading clipboard image: $e")
                        result.success(null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        inputManager?.unregisterInputDeviceListener(this)
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

    override fun onInputDeviceRemoved(deviceId: Int) {}

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val toolType = event.getToolType(0)
        if (toolType == MotionEvent.TOOL_TYPE_STYLUS || toolType == MotionEvent.TOOL_TYPE_ERASER) {
            checkAndNotifyStylus()
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        val toolType = event.getToolType(0)
        if (toolType == MotionEvent.TOOL_TYPE_STYLUS || toolType == MotionEvent.TOOL_TYPE_ERASER) {
            checkAndNotifyStylus()
        }
        return super.dispatchTouchEvent(event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Intercept vendor stylus button keycodes (Lenovo Pen Plus sends 600-604, 289, 290)
        // Consuming them here prevents Android's ViewRootImpl input stage from stalling (ANR)
        val keyCode = event.keyCode
        val isLenovoPenKey = keyCode in 600..604 || keyCode == 289 || keyCode == 290 ||
                keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_PRIMARY ||
                keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_SECONDARY ||
                keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_TERTIARY ||
                keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_TAIL

        if (isLenovoPenKey) {
            Log.d("PdfReorPen", "Pen Key: action=${event.action}, code=$keyCode, repeat=${event.repeatCount}")
            if (event.action == KeyEvent.ACTION_DOWN) {
                if (event.repeatCount == 0) {
                    runOnUiThread {
                        stylusChannel?.invokeMethod("onStylusButtonDown", null)
                    }
                }
            } else if (event.action == KeyEvent.ACTION_UP) {
                runOnUiThread {
                    stylusChannel?.invokeMethod("onStylusButtonUp", null)
                }
            }
            return true // Consume key event immediately! Prevents ANR!
        }
        return super.dispatchKeyEvent(event)
    }
}
