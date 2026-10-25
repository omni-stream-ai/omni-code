package com.omnistreamai.code

import android.content.Context
import android.view.inputmethod.InputMethodManager
import android.webkit.WebView
import android.view.View
import android.view.ViewGroup
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "omni_code/app_update"

    private fun configureWebViewProxy(host: String?, result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.success(false)
            return
        }
        val proxy = ProxyConfig.Builder()
            .addDirect()
            .build()
        ProxyController.getInstance().setProxyOverride(proxy, { command -> command.run() }) {
            result.success(true)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showDesktopKeyboard" -> {
                        fun findWebView(view: View): WebView? {
                            if (view is WebView) return view
                            if (view is ViewGroup) {
                                for (i in 0 until view.childCount) {
                                    findWebView(view.getChildAt(i))?.let { return it }
                                }
                            }
                            return null
                        }
                        val webView = findWebView(window.decorView)
                        if (webView == null) result.success(false)
                        else {
                            webView.requestFocus()
                            webView.post {
                                val ime = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                                result.success(ime.showSoftInput(webView, InputMethodManager.SHOW_IMPLICIT))
                            }
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK path is empty", null)
                            return@setMethodCallHandler
                        }
                        installApk(path, result)
                    }
                    "configureWebViewProxy" -> {
                        val host = call.argument<String>("host")
                        if (host !in setOf("10.0.2.2", "localhost", "127.0.0.1")) {
                            result.success(false)
                        } else if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                            result.success(false)
                        } else {
                            configureWebViewProxy(host, result)
                        }
                    }
                    "clearWebViewProxy" -> {
                        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                            result.success(false)
                        } else {
                            ProxyController.getInstance().clearProxyOverride(
                                { command -> command.run() },
                            ) { result.success(true) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.error("INSTALL_PERMISSION_REQUIRED", "请允许 Omni Code 安装未知来源应用后重试", null)
            return
        }

        val file = File(path)
        if (!file.exists()) {
            result.error("FILE_NOT_FOUND", "APK file does not exist", null)
            return
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.update_file_provider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
        result.success(null)
    }
}
