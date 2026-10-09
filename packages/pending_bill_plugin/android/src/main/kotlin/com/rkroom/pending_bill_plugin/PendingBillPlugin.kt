package com.rkroom.pending_bill_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class PendingBillPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "com.rkroom.simple_account/pending_bills"

        @Volatile private var pendingBillCountProvider: PendingBillCountProvider? = null

        @JvmStatic
        fun setPendingBillCountProvider(provider: PendingBillCountProvider) {
            pendingBillCountProvider = provider
        }
    }

    private var channel: MethodChannel? = null
    private var pluginScope: CoroutineScope? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        pluginScope?.cancel()
        pluginScope = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "getPendingBillCount") {
            result.notImplemented()
            return
        }

        val provider = pendingBillCountProvider
        if (provider == null) {
            result.error(
                    "UNAVAILABLE",
                    "Pending bill count provider has not been initialized",
                    null
            )
            return
        }

        val scope = pluginScope
        if (scope == null) {
            result.error("UNAVAILABLE", "Pending bill plugin is detached", null)
            return
        }

        scope.launch {
            try {
                result.success(provider.getPendingBillCount().coerceAtLeast(0))
            } catch (_: CancellationException) {
                // The engine was detached before the native query completed.
            } catch (error: Exception) {
                result.error("READ_FAILED", error.message, null)
            }
        }
    }
}
