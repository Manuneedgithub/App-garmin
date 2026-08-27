package com.tonnom.baskettrainer.garmin

import android.content.Context
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQDevice
import com.garmin.android.connectiq.exception.InvalidStateException
import com.garmin.android.connectiq.exception.ServiceUnavailableException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

object GarminManager {
    // Doit rester identique à garmin-app/manifest.xml et
    // ios-app/BasketTrainer/Managers/GarminManager.swift.
    const val APP_UUID = "a3d5e7f9-1b2c-4d6e-8f0a-2b4c6d8e0f1a"

    private lateinit var connectIQ: ConnectIQ
    private lateinit var appContext: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _connectedDevice = MutableStateFlow<IQDevice?>(null)
    val connectedDevice: StateFlow<IQDevice?> get() = _connectedDevice

    private val _garminConnectAvailable = MutableStateFlow(true)
    val garminConnectAvailable: StateFlow<Boolean> get() = _garminConnectAvailable

    private val connectIQListener = object : ConnectIQ.ConnectIQListener {
        override fun onSdkReady() {
            connectWatch()
        }

        override fun onInitializeError(errStatus: ConnectIQ.IQSdkErrorStatus) {
            _garminConnectAvailable.value = false
        }

        override fun onSdkShutDown() {}
    }

    fun init(context: Context) {
        appContext = context.applicationContext
        connectIQ = ConnectIQ.getInstance(appContext, ConnectIQ.IQConnectType.WIRELESS)
        connectIQ.initialize(appContext, true, connectIQListener)
    }

    fun connectWatch() {
        scope.launch {
            val devices = try {
                connectIQ.knownDevices ?: emptyList()
            } catch (e: InvalidStateException) {
                emptyList()
            } catch (e: ServiceUnavailableException) {
                _garminConnectAvailable.value = false
                emptyList()
            }

            devices.forEach { device ->
                connectIQ.unregisterForDeviceEvents(device)
                connectIQ.registerForDeviceEvents(device) { updatedDevice, status ->
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                        _connectedDevice.value = updatedDevice
                        registerForAppMessages(updatedDevice)
                    } else if (_connectedDevice.value?.deviceIdentifier == updatedDevice.deviceIdentifier) {
                        _connectedDevice.value = null
                    }
                }
            }
        }
    }

    private fun registerForAppMessages(device: IQDevice) {
        // Extended in Task 6 to parse and store incoming sessions.
    }
}
