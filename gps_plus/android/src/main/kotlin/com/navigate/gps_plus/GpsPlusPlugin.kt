package com.navigate.gps_plus

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.CellIdentityGsm
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellIdentityWcdma
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrengthGsm
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.CellSignalStrengthWcdma
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class GpsPlusPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "gps_plus")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getCellTowers" -> getCellTowers(result)
            else -> result.notImplemented()
        }
    }

    private fun getCellTowers(result: Result) {
        // Check permissions
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "PERMISSION_DENIED",
                "ACCESS_FINE_LOCATION permission is required",
                null
            )
            return
        }

        try {
            val telephonyManager =
                context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val cellInfoList = telephonyManager.allCellInfo

            if (cellInfoList == null || cellInfoList.isEmpty()) {
                result.success(emptyList<Map<String, Any>>())
                return
            }

            val towers = mutableListOf<Map<String, Any>>()

            for (cellInfo in cellInfoList) {
                val towerMap = parseCellInfo(cellInfo)
                if (towerMap != null) {
                    towers.add(towerMap)
                }
            }

            result.success(towers)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message, null)
        } catch (e: Exception) {
            result.error("CELL_INFO_ERROR", e.message, null)
        }
    }

    private fun parseCellInfo(cellInfo: CellInfo): Map<String, Any>? {
        return when (cellInfo) {
            is CellInfoGsm -> parseGsm(cellInfo)
            is CellInfoLte -> parseLte(cellInfo)
            is CellInfoWcdma -> parseWcdma(cellInfo)
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && cellInfo is CellInfoNr) {
                    parseNr(cellInfo)
                } else {
                    null
                }
            }
        }
    }

    private fun parseGsm(info: CellInfoGsm): Map<String, Any>? {
        val identity = info.cellIdentity
        val signal = info.cellSignalStrength

        val cid = identity.cid
        val lac = identity.lac
        val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            identity.mccString?.toIntOrNull() ?: return null
        } else {
            @Suppress("DEPRECATION")
            identity.mcc
        }
        val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            identity.mncString?.toIntOrNull() ?: return null
        } else {
            @Suppress("DEPRECATION")
            identity.mnc
        }

        if (cid == Int.MAX_VALUE || lac == Int.MAX_VALUE) return null
        if (mcc == Int.MAX_VALUE || mnc == Int.MAX_VALUE) return null

        return mapOf(
            "cid" to cid,
            "lac" to lac,
            "mcc" to mcc,
            "mnc" to mnc,
            "rssi" to signal.dbm,
            "type" to "gsm",
            "timestamp" to System.currentTimeMillis()
        )
    }

    private fun parseLte(info: CellInfoLte): Map<String, Any>? {
        val identity = info.cellIdentity
        val signal = info.cellSignalStrength

        val cid = identity.ci
        val lac = identity.tac
        val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            identity.mccString?.toIntOrNull() ?: return null
        } else {
            @Suppress("DEPRECATION")
            identity.mcc
        }
        val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            identity.mncString?.toIntOrNull() ?: return null
        } else {
            @Suppress("DEPRECATION")
            identity.mnc
        }

        if (cid == Int.MAX_VALUE || lac == Int.MAX_VALUE) return null
        if (mcc == Int.MAX_VALUE || mnc == Int.MAX_VALUE) return null

        return mapOf(
            "cid" to cid,
            "lac" to lac,
            "mcc" to mcc,
            "mnc" to mnc,
            "rssi" to signal.dbm,
            "type" to "lte",
            "timestamp" to System.currentTimeMillis()
        )
    }

    private fun parseWcdma(info: CellInfoWcdma): Map<String, Any>? {
        val identity = info.cellIdentity
        val signal = info.cellSignalStrength

        val cid = identity.cid
        val lac = identity.lac
        val mcc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            identity.mccString?.toIntOrNull() ?: return null
        } else {
            @Suppress("DEPRECATION")
            identity.mcc
        }
        val mnc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            identity.mncString?.toIntOrNull() ?: return null
        } else {
            @Suppress("DEPRECATION")
            identity.mnc
        }

        if (cid == Int.MAX_VALUE || lac == Int.MAX_VALUE) return null
        if (mcc == Int.MAX_VALUE || mnc == Int.MAX_VALUE) return null

        return mapOf(
            "cid" to cid,
            "lac" to lac,
            "mcc" to mcc,
            "mnc" to mnc,
            "rssi" to signal.dbm,
            "type" to "umts",
            "timestamp" to System.currentTimeMillis()
        )
    }

    private fun parseNr(cellInfo: CellInfo): Map<String, Any>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null

        val info = cellInfo as CellInfoNr
        val identity = info.cellIdentity as android.telephony.CellIdentityNr
        val signal = info.cellSignalStrength as CellSignalStrengthNr

        val cid = identity.nci.toInt()
        val lac = identity.tac
        val mcc = identity.mccString?.toIntOrNull() ?: return null
        val mnc = identity.mncString?.toIntOrNull() ?: return null

        if (lac == Int.MAX_VALUE) return null

        return mapOf(
            "cid" to cid,
            "lac" to lac,
            "mcc" to mcc,
            "mnc" to mnc,
            "rssi" to signal.dbm,
            "type" to "nr",
            "timestamp" to System.currentTimeMillis()
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
