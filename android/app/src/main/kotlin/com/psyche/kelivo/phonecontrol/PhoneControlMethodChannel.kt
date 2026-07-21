package com.psyche.kelivo.phonecontrol

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.accessibilityservice.AccessibilityService
import android.provider.Settings
import rikka.shizuku.Shizuku
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object PhoneControlMethodChannel {
    private const val CHANNEL = "baizi.phone_control"
    private const val EVENTS_CHANNEL = "baizi.phone_control.events"
    private const val SHIZUKU_REQUEST = 9182
    private val executor = Executors.newSingleThreadExecutor()
    private var eventSink: EventChannel.EventSink? = null
    private var authorizationPending = false

    private val permissionResultListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode != SHIZUKU_REQUEST) return@OnRequestPermissionResultListener
            authorizationPending = false
            eventSink?.success(
                status("granted".takeIf { grantResult == PackageManager.PERMISSION_GRANTED }
                    ?: "denied"),
            )
        }

    fun install(context: Context, messenger: BinaryMessenger) {
        Shizuku.addRequestPermissionResultListener(permissionResultListener)
        EventChannel(messenger, EVENTS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    events?.success(status())
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> result.success(status())
                "requestShizuku" -> {
                    when {
                        !isShizukuRunning() -> result.success(status("not_running"))
                        hasShizukuPermission() -> result.success(status("already_granted"))
                        authorizationPending -> result.success(status("pending"))
                        else -> try {
                            authorizationPending = true
                            Shizuku.requestPermission(SHIZUKU_REQUEST)
                            result.success(status("pending"))
                        } catch (e: Throwable) {
                            authorizationPending = false
                            result.success(status("request_failed", e.message))
                        }
                    }
                }
                "openAccessibilitySettings" -> {
                    context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "execute" -> {
                    @Suppress("UNCHECKED_CAST") val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    executor.execute {
                        try { result.success(execute(context, args)) }
                        catch (e: Throwable) { result.success(error("execution_error", e.message ?: e.javaClass.simpleName)) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun status(
        authorizationState: String? = null,
        authorizationMessage: String? = null,
    ): Map<String, Any?> {
        val shizukuRunning = isShizukuRunning()
        val shizukuGranted = shizukuRunning && hasShizukuPermission()
        return mapOf(
            "shizukuRunning" to shizukuRunning,
            "shizukuGranted" to shizukuGranted,
            "shizukuAuthorizationState" to (
                authorizationState ?: if (shizukuGranted) "granted" else if (authorizationPending) "pending" else "idle"
            ),
            "shizukuAuthorizationMessage" to authorizationMessage,
            "rootAvailable" to rootAvailable(),
            "accessibilityEnabled" to (PhoneControlAccessibilityService.instance != null),
        )
    }

    private fun isShizukuRunning(): Boolean = try { Shizuku.pingBinder() } catch (_: Throwable) { false }
    private fun hasShizukuPermission(): Boolean = try {
        Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Throwable) { false }

    private fun execute(context: Context, args: Map<String, Any?>): Map<String, Any?> {
        val action = args["action"]?.toString()?.trim().orEmpty()
        if (action.isEmpty()) return error("invalid_arguments", "action is required")
        val service = PhoneControlAccessibilityService.instance
        return when (action) {
            "get_status" -> ok("Current capability status", status())
            "get_ui_tree" -> service?.uiTree()?.let { ok("Read current UI tree", mapOf("uiTree" to it)) }
                ?: error("accessibility_unavailable", "Enable Baizi accessibility service first")
            "tap" -> accessResult(service?.tap(args["text"]?.toString(), intArg(args, "x"), intArg(args, "y")) == true, "Tap completed")
            "long_press" -> accessResult(service?.longPress(args["text"]?.toString(), intArg(args, "x"), intArg(args, "y")) == true, "Long press completed")
            "input_text" -> accessResult(service?.input(args["text"]?.toString().orEmpty()) == true, "Text input completed")
            "scroll" -> accessResult(service?.scroll(args["direction"]?.toString() != "backward") == true, "Scroll completed")
            "back" -> accessResult(service?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK) == true, "Returned")
            "home" -> accessResult(service?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME) == true, "Opened home")
            "open_notifications" -> accessResult(service?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS) == true, "Opened notifications")
            "launch_app" -> launchApp(context, args["packageName"]?.toString())
            "list_apps" -> ok("Installed applications", mapOf("packages" to context.packageManager.getInstalledApplications(0).take(300).map { it.packageName }))
            "stop_app" -> shell("am force-stop ${quote(args["packageName"]?.toString().orEmpty())}")
            "set_volume" -> shell("media volume --show ${intArg(args, "level") ?: return error("invalid_arguments", "level is required")}")
            "set_brightness" -> shell("settings put system screen_brightness ${intArg(args, "level") ?: return error("invalid_arguments", "level is required")}")
            "run_shell" -> shell(args["command"]?.toString().orEmpty())
            "file_operation" -> fileOperation(args)
            else -> error("unsupported_action", "Unsupported phone control action: $action")
        }
    }

    private fun launchApp(context: Context, packageName: String?): Map<String, Any?> {
        if (packageName.isNullOrBlank()) return error("invalid_arguments", "packageName is required")
        val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            ?: return error("app_not_found", "No launchable app found for $packageName")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return ok("Launched $packageName")
    }

    private fun fileOperation(args: Map<String, Any?>): Map<String, Any?> {
        val operation = args["operation"]?.toString().orEmpty()
        val path = args["path"]?.toString().orEmpty()
        if (operation.isEmpty() || path.isEmpty()) return error("invalid_arguments", "operation and path are required")
        return when (operation) {
            "list" -> shell("ls -la ${quote(path)}")
            "read" -> shell("cat ${quote(path)}")
            "delete" -> shell("rm -rf ${quote(path)}")
            "mkdir" -> shell("mkdir -p ${quote(path)}")
            "move" -> shell("mv ${quote(path)} ${quote(args["destination"]?.toString().orEmpty())}")
            "copy" -> shell("cp -R ${quote(path)} ${quote(args["destination"]?.toString().orEmpty())}")
            "zip" -> shell("zip -r ${quote(args["destination"]?.toString().orEmpty())} ${quote(path)}")
            "unzip" -> shell("unzip -o ${quote(path)} -d ${quote(args["destination"]?.toString().orEmpty())}")
            else -> error("unsupported_file_operation", "Unsupported file operation: $operation")
        }
    }

    private fun shell(command: String): Map<String, Any?> {
        if (command.isBlank()) return error("invalid_arguments", "command is required")
        val result = if (status()["shizukuGranted"] == true) runShizuku(command) else if (rootAvailable()) runRoot(command) else null
        return result ?: error("shell_unavailable", "Connect Shizuku or grant Root access to run this action")
    }

    private fun runShizuku(command: String): Map<String, Any?> = try {
        // Shizuku exposes process execution as a restricted Java API. Resolve it
        // from the bundled library at runtime so Kotlin does not reject it.
        val processMethod = Shizuku::class.java.getDeclaredMethod(
            "newProcess",
            Array<String>::class.java,
            Array<String>::class.java,
            String::class.java,
        ).apply { isAccessible = true }
        val process = processMethod.invoke(null, arrayOf("sh", "-c", command), null, null) as Process
        val output = BufferedReader(InputStreamReader(process.inputStream)).readText().take(12000)
        val errors = BufferedReader(InputStreamReader(process.errorStream)).readText().take(4000)
        process.waitFor()
        if (process.exitValue() == 0) ok("Command completed", mapOf("output" to output, "channel" to "shizuku"))
        else error("command_failed", errors.ifBlank { output }, mapOf("channel" to "shizuku", "exitCode" to process.exitValue()))
    } catch (e: Throwable) { error("shizuku_execution_failed", e.message ?: "Shizuku command failed") }

    private fun runRoot(command: String): Map<String, Any?> {
        return try {
            val process = ProcessBuilder("su", "-c", command).redirectErrorStream(true).start()
            val output = BufferedReader(InputStreamReader(process.inputStream)).readText().take(12000)
            if (!process.waitFor(20, TimeUnit.SECONDS)) {
                process.destroyForcibly()
                error("command_timeout", "Command timed out")
            } else if (process.exitValue() == 0) {
                ok("Command completed", mapOf("output" to output, "channel" to "root"))
            } else {
                error("command_failed", output, mapOf("channel" to "root", "exitCode" to process.exitValue()))
            }
        } catch (e: Throwable) {
            error("root_execution_failed", e.message ?: "Root command failed")
        }
    }

    private fun rootAvailable(): Boolean = try {
        val process = ProcessBuilder("su", "-c", "id").start()
        process.waitFor(2, TimeUnit.SECONDS) && process.exitValue() == 0
    } catch (_: Throwable) { false }
    private fun intArg(args: Map<String, Any?>, key: String) = (args[key] as? Number)?.toInt() ?: args[key]?.toString()?.toIntOrNull()
    private fun quote(value: String) = "'" + value.replace("'", "'\\\"'\\\"'") + "'"
    private fun ok(summary: String, details: Map<String, Any?> = emptyMap()) = mapOf("status" to "success", "summary" to summary, "details" to details)
    private fun error(code: String, message: String, details: Map<String, Any?> = emptyMap()) = mapOf("status" to "error", "error" to code, "summary" to message, "details" to details)
    private fun accessResult(success: Boolean, summary: String) = if (success) ok(summary) else error("accessibility_action_failed", "Unable to complete action. Check the current screen and accessibility service.")
}
