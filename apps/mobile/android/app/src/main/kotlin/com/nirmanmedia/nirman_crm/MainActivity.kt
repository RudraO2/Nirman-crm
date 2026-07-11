package com.nirmanmedia.nirman_crm

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Story 10.2/10.3 — full-screen-intent special access. On Android 14+ (API 34)
    // USE_FULL_SCREEN_INTENT is NOT auto-granted for non-call/alarm apps, so a
    // backgrounded alarm degrades to a heads-up notification (sound only, no
    // full-screen ring). permission_handler has no API for this; we check
    // canUseFullScreenIntent() and route the user to the dedicated settings page.
    private val channelName = "nirman/alarm_permissions"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(null)
                    }
                    // Story 10.4 — OEM auto-start guidance.
                    "getAutoStartInfo" -> result.success(getAutoStartInfo())
                    "openAutoStartSettings" -> {
                        openAutoStartSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Story 10.4 — Per-OEM "Autostart"/"Auto-launch" manager components. Aggressive
    // OEMs (Xiaomi/MIUI, Oppo & Realme/ColorOS, Vivo/Funtouch, Huawei/EMUI, etc.)
    // stop background alarms unless the app is allow-listed here — the top cause of
    // alarms not firing after task-kill or reboot on those phones. There is NO OS
    // API to READ this state; we can only deep-link the user to the page. Several
    // candidates per OEM (skin/version drift); we launch the first that resolves.
    // Source: the "Don't kill my app!" (dontkillmyapp.com) component catalogue.
    private val autoStartComponents: List<ComponentName> = listOf(
        // Xiaomi / Redmi / Poco (MIUI)
        ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        // Oppo / Realme (ColorOS)
        ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
        ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
        ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
        ComponentName("com.oplus.safecenter", "com.oplus.safecenter.permission.startup.StartupAppListActivity"),
        // Vivo / iQOO (Funtouch OS)
        ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
        ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
        ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
        // Huawei / Honor (EMUI)
        ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
        // Samsung (Device care)
        ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
        ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity"),
        // Asus (Mobile Manager)
        ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.MainActivity"),
        ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.entry.FunctionActivity"),
        // OnePlus
        ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
        // Letv / LeEco
        ComponentName("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"),
        // Meizu
        ComponentName("com.meizu.safe", "com.meizu.safe.permission.SmartBGActivity"),
    )

    /// Returns {manufacturer, componentResolved}. `componentResolved` is a
    /// best-effort probe — Android 11+ package visibility can hide these
    /// components, so the Dart side ALSO shows the step for known-aggressive
    /// manufacturers (see oem_autostart.dart) even when this is false.
    private fun getAutoStartInfo(): Map<String, Any> {
        val resolved = autoStartComponents.any { component ->
            try {
                val intent = Intent().setComponent(component)
                packageManager.resolveActivity(intent, 0) != null
            } catch (e: Exception) {
                false
            }
        }
        return mapOf(
            "manufacturer" to (Build.MANUFACTURER ?: ""),
            "brand" to (Build.BRAND ?: ""),
            "componentResolved" to resolved,
        )
    }

    /// Launches the first OEM auto-start page that starts successfully; on any
    /// failure (component absent, visibility-blocked, security) falls back to this
    /// app's system settings page so the user never dead-ends (AC2/AC4).
    private fun openAutoStartSettings() {
        for (component in autoStartComponents) {
            try {
                startActivity(
                    Intent().setComponent(component)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                return
            } catch (e: Exception) {
                // Try the next candidate.
            }
        }
        // Fallback — app details / settings page.
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            // Nothing more we can do; swallow so the channel call still succeeds.
        }
    }

    private fun canUseFullScreenIntent(): Boolean {
        // Pre-14: the manifest permission is enough; treat as granted.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.canUseFullScreenIntent()
    }

    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // No dedicated screen pre-14; fall back to the app's notification settings.
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return
        }
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
