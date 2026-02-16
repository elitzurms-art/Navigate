package com.elitzur_software.navigate

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.elitzur.navigate/security"
    private var methodChannel: MethodChannel? = null
    private var devicePolicyManager: DevicePolicyManager? = null
    private var adminComponentName: ComponentName? = null

    // מעקב מצב Lock Task לזיהוי יציאה
    private var wasInLockTaskMode = false

    // BroadcastReceiver לזיהוי אירועי מערכת
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    methodChannel?.invokeMethod("onScreenOff", null)
                }
                Intent.ACTION_SCREEN_ON -> {
                    methodChannel?.invokeMethod("onScreenOn", null)
                }
                Intent.ACTION_USER_PRESENT -> {
                    // מסך נפתח אחרי unlock
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponentName = ComponentName(this, DeviceAdminReceiver::class.java)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableLockTask" -> {
                    result.success(enableLockTaskMode())
                }
                "disableLockTask" -> {
                    val unlockCode = call.argument<String>("unlockCode")
                    result.success(disableLockTaskMode(unlockCode))
                }
                "isInLockTaskMode" -> {
                    result.success(isInLockTaskMode())
                }
                "isDeviceOwner" -> {
                    result.success(isDeviceOwner())
                }
                "enableKioskMode" -> {
                    result.success(enableKioskMode())
                }
                "disableKioskMode" -> {
                    val adminCode = call.argument<String>("adminCode")
                    result.success(disableKioskMode(adminCode))
                }
                "isGPSEnabled" -> {
                    result.success(isGPSEnabled())
                }
                "isInternetConnected" -> {
                    result.success(isInternetConnected())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // רישום BroadcastReceiver לאירועי מסך
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(screenReceiver)
    }

    override fun onResume() {
        super.onResume()
        // זיהוי יציאה מ-Lock Task Mode
        val currentlyInLockTask = isInLockTaskMode()
        if (wasInLockTaskMode && !currentlyInLockTask) {
            methodChannel?.invokeMethod("onLockTaskExit", null)
        }
        wasInLockTaskMode = currentlyInLockTask
    }

    override fun onPause() {
        super.onPause()
        // דיווח על מעבר לרקע
        if (isInLockTaskMode()) {
            methodChannel?.invokeMethod("onAppBackgrounded", null)
        }
    }

    // ========== Lock Task Mode Functions ==========

    private fun enableLockTaskMode(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                startLockTask()
                wasInLockTaskMode = true
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun disableLockTaskMode(unlockCode: String?): Boolean {
        return try {
            // TODO: בדיקת קוד נכון
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                stopLockTask()
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun isInLockTaskMode(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            false
        }
    }

    // ========== Device Owner Functions ==========

    private fun isDeviceOwner(): Boolean {
        return devicePolicyManager?.isDeviceOwnerApp(packageName) ?: false
    }

    private fun enableKioskMode(): Boolean {
        if (!isDeviceOwner()) return false

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                devicePolicyManager?.setLockTaskPackages(
                    adminComponentName,
                    arrayOf(packageName)
                )
                startLockTask()
                wasInLockTaskMode = true
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun disableKioskMode(adminCode: String?): Boolean {
        if (!isDeviceOwner()) return false

        return try {
            // TODO: בדיקת קוד מנהל
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                stopLockTask()
                devicePolicyManager?.setLockTaskPackages(adminComponentName, arrayOf())
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    // ========== Helper Functions ==========

    private fun isGPSEnabled(): Boolean {
        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    private fun isInternetConnected(): Boolean {
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = connectivityManager.activeNetwork ?: return false
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } else {
            @Suppress("DEPRECATION")
            connectivityManager.activeNetworkInfo?.isConnected ?: false
        }
    }
}

// Device Admin Receiver (נדרש ל-Device Owner)
class DeviceAdminReceiver : android.app.admin.DeviceAdminReceiver()
