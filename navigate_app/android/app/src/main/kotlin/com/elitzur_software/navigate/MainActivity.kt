package com.elitzur_software.navigate

import android.app.ActivityManager
import android.app.NotificationManager
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
import android.provider.Settings
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import com.google.android.gms.auth.api.identity.GetPhoneNumberHintIntentRequest
import com.google.android.gms.auth.api.identity.Identity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.elitzur.navigate/security"
    private var methodChannel: MethodChannel? = null
    private var devicePolicyManager: DevicePolicyManager? = null
    private var adminComponentName: ComponentName? = null

    // Phone Number Hint (auth channel)
    private val AUTH_CHANNEL = "com.elitzur.navigate/auth"
    private var authMethodChannel: MethodChannel? = null
    private var phoneHintResult: MethodChannel.Result? = null
    private lateinit var phoneHintLauncher: ActivityResultLauncher<IntentSenderRequest>

    // מעקב מצב Lock Task לזיהוי יציאה
    private var wasInLockTaskMode = false

    // DND — שמירת מצב קודם לשחזור
    private var previousInterruptionFilter: Int = NotificationManager.INTERRUPTION_FILTER_ALL

    // Call monitoring
    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var telephonyCallback: Any? = null // TelephonyCallback for API 31+

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
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        // Auth channel — Phone Number Hint
        authMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTH_CHANNEL)
        authMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPhoneNumberHint" -> requestPhoneNumberHint(result)
                else -> result.notImplemented()
            }
        }

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
                // ========== DND Functions ==========
                "enableDND" -> {
                    result.success(enableDND())
                }
                "disableDND" -> {
                    result.success(disableDND())
                }
                "isDNDEnabled" -> {
                    result.success(isDNDEnabled())
                }
                "hasDNDPermission" -> {
                    result.success(hasDNDPermission())
                }
                "requestDNDPermission" -> {
                    requestDNDPermission()
                    result.success(true)
                }
                // ========== Call Monitoring ==========
                "startCallMonitoring" -> {
                    startCallMonitoring()
                    result.success(true)
                }
                "stopCallMonitoring" -> {
                    stopCallMonitoring()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Register ActivityResultLauncher BEFORE super.onCreate()
        phoneHintLauncher = registerForActivityResult(
            ActivityResultContracts.StartIntentSenderForResult()
        ) { result ->
            val pending = phoneHintResult
            phoneHintResult = null
            if (result.resultCode == RESULT_OK && result.data != null) {
                try {
                    val phone = Identity.getSignInClient(this)
                        .getPhoneNumberFromIntent(result.data!!)
                    pending?.success(phone)
                } catch (e: Exception) {
                    pending?.success(null)
                }
            } else {
                pending?.success(null)
            }
        }

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
        stopCallMonitoring()
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
    }

    override fun onStop() {
        super.onStop()
        // דיווח על מעבר לרקע — רק כשהמסך דלוק (screen-off מטופל ב-screenReceiver)
        if (isInLockTaskMode()) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            if (powerManager.isInteractive) {
                methodChannel?.invokeMethod("onAppBackgrounded", null)
            }
        }
    }

    // ========== Lock Task Mode Functions ==========

    private fun enableLockTaskMode(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                startLockTask()
                // wasInLockTaskMode will be set in onResume() based on actual state
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
                // wasInLockTaskMode will be set in onResume() based on actual state
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

    // ========== DND (Do Not Disturb) Functions ==========

    private fun enableDND(): Boolean {
        return try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!notificationManager.isNotificationPolicyAccessGranted) {
                return false
            }
            val currentFilter = notificationManager.currentInterruptionFilter
            // Already in DND — no-op, prevents previousInterruptionFilter corruption
            if (currentFilter == NotificationManager.INTERRUPTION_FILTER_ALARMS) {
                return true
            }
            // Save previous filter only when transitioning from normal → DND
            if (currentFilter == NotificationManager.INTERRUPTION_FILTER_ALL) {
                previousInterruptionFilter = currentFilter
            }
            notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun disableDND(): Boolean {
        return try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!notificationManager.isNotificationPolicyAccessGranted) {
                return false
            }
            // Always fully disable DND — eliminates previousInterruptionFilter corruption vector
            notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun isDNDEnabled(): Boolean {
        return try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
        } catch (e: Exception) {
            false
        }
    }

    private fun hasDNDPermission(): Boolean {
        return try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.isNotificationPolicyAccessGranted
        } catch (e: Exception) {
            false
        }
    }

    private fun requestDNDPermission() {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ========== Call Monitoring Functions ==========

    private fun startCallMonitoring() {
        stopCallMonitoring() // ניקוי listener קודם

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // API 31+ — TelephonyCallback
                startCallMonitoringApi31()
            } else {
                // API < 31 — PhoneStateListener
                startCallMonitoringLegacy()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun startCallMonitoringApi31() {
        val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
            override fun onCallStateChanged(state: Int) {
                if (state == TelephonyManager.CALL_STATE_OFFHOOK) {
                    methodChannel?.invokeMethod("onCallAnswered", null)
                }
            }
        }
        telephonyCallback = callback
        telephonyManager?.registerTelephonyCallback(mainExecutor, callback)
    }

    @Suppress("DEPRECATION")
    private fun startCallMonitoringLegacy() {
        val listener = object : PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                if (state == TelephonyManager.CALL_STATE_OFFHOOK) {
                    methodChannel?.invokeMethod("onCallAnswered", null)
                }
            }
        }
        phoneStateListener = listener
        telephonyManager?.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
    }

    @Suppress("DEPRECATION")
    private fun stopCallMonitoring() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && telephonyCallback != null) {
                telephonyManager?.unregisterTelephonyCallback(telephonyCallback as TelephonyCallback)
                telephonyCallback = null
            } else if (phoneStateListener != null) {
                telephonyManager?.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE)
                phoneStateListener = null
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ========== Phone Number Hint ==========

    private fun requestPhoneNumberHint(result: MethodChannel.Result) {
        if (phoneHintResult != null) { result.success(null); return }
        phoneHintResult = result
        val request = GetPhoneNumberHintIntentRequest.builder().build()
        Identity.getSignInClient(this)
            .getPhoneNumberHintIntent(request)
            .addOnSuccessListener { pendingIntent ->
                try {
                    phoneHintLauncher.launch(
                        IntentSenderRequest.Builder(pendingIntent.intentSender).build()
                    )
                } catch (e: Exception) {
                    phoneHintResult = null
                    result.success(getPhoneFromTelephony())
                }
            }
            .addOnFailureListener {
                phoneHintResult = null
                result.success(getPhoneFromTelephony())
            }
    }

    @Suppress("DEPRECATION")
    private fun getPhoneFromTelephony(): String? {
        return try {
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                checkSelfPermission(android.Manifest.permission.READ_PHONE_NUMBERS) == android.content.pm.PackageManager.PERMISSION_GRANTED
            } else {
                checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) == android.content.pm.PackageManager.PERMISSION_GRANTED
            }
            if (!hasPermission) return null

            val number = tm.line1Number
            if (!number.isNullOrBlank()) return number

            // Fallback: SubscriptionManager
            val subMgr = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? android.telephony.SubscriptionManager
            val subNumber = subMgr?.activeSubscriptionInfoList?.firstOrNull()?.number
            if (!subNumber.isNullOrBlank()) return subNumber

            null
        } catch (e: Exception) {
            null
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
