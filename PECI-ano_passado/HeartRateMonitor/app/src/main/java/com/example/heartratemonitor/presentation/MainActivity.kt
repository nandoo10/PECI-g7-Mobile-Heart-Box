package com.example.heartratemonitor.presentation

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.*
import android.util.Log
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.heartratemonitor.R
import kotlinx.coroutines.*
import java.util.*

class MainActivity : ComponentActivity(), SensorEventListener {

    private val TAG = "HeartRateBLE"

    private lateinit var sensorManager: SensorManager
    private var heartRateSensor: Sensor? = null
    private var heartRate by mutableStateOf(0f)

    private lateinit var bluetoothManager: BluetoothManager
    private lateinit var bluetoothAdapter: BluetoothAdapter
    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private val connectedDevices = mutableSetOf<BluetoothDevice>()

    private val CUSTOM_SERVICE_UUID = UUID.fromString("e626a696-36ba-45b3-a444-5c28eb674dd5")
    private val CUSTOM_CHARACTERISTIC_UUID = UUID.fromString("aa4fe3ac-56c4-42c7-856e-500b8d4b1a01")
    private val CLIENT_CHARACTERISTIC_CONFIG_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private var sendJob: Job? = null
    private var isAdvertising = false
    private var isGattServerStarted = false
    private var isSensorRegistered = false
    private var isSendingLoopRunning = false

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.i(TAG, "Advertising iniciado com UUID customizado")
            isAdvertising = true
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "Erro no advertising: $errorCode")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        heartRateSensor = sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE)

        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        advertiser = bluetoothAdapter.bluetoothLeAdvertiser

        requestPermissions()

        setContent {
            MaterialTheme(colors = MaterialTheme.colors.copy(background = Color.Black)) {
                MainScreen(heartRate)
            }
        }
    }

    private fun requestPermissions() {
        val permissions = mutableListOf(Manifest.permission.BODY_SENSORS)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += listOf(
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            permissions += Manifest.permission.ACCESS_FINE_LOCATION
        }

        val allGranted = permissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

        if (allGranted) {
            startEverything()
        } else {
            requestPermissionLauncher.launch(permissions.toTypedArray())
        }
    }

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (permissions.values.all { it }) {
            startEverything()
        } else {
            Log.e(TAG, "Permissões BLE/sensor não concedidas")
        }
    }

    private fun startEverything() {
        registerSensor()
        startGattServer()
        startAdvertising()
        startSendingLoop()
    }

    private fun registerSensor() {
        if (!isSensorRegistered) {
            heartRateSensor?.let {
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
                isSensorRegistered = true
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_HEART_RATE) {
            heartRate = event.values.firstOrNull() ?: return
            Log.i(TAG, "BPM detectado: $heartRate")
        }
    }

    private fun startSendingLoop() {
        if (!isSendingLoopRunning) {
            sendJob = CoroutineScope(Dispatchers.IO).launch {
                isSendingLoopRunning = true
                while (isActive) {
                    delay(1000)
                    sendHeartRate()
                }
            }
        }
    }

    private fun sendHeartRate() {
        val bpm = heartRate.toInt()
        val timestampMs = SystemClock.elapsedRealtimeNanos() / 1_000_000
        val timestampStr = timestampMs.toString().take(14)
        val payload = "sw$timestampStr.$bpm"

        if (payload.length > 20) {
            Log.w(TAG, "Payload excede 20 caracteres: $payload")
            return
        }

        val payloadBytes = payload.toByteArray()

        val characteristic = gattServer
            ?.getService(CUSTOM_SERVICE_UUID)
            ?.getCharacteristic(CUSTOM_CHARACTERISTIC_UUID) ?: return

        characteristic.value = payloadBytes

        connectedDevices.forEach { device ->
            try {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                    Log.i(TAG, "Enviando via BLE: $payload")
                    gattServer?.notifyCharacteristicChanged(device, characteristic, false)
                } else {
                    Log.w(TAG, "Sem permissão BLUETOOTH_CONNECT para notificar ${device.address}")
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "SecurityException ao tentar notificar ${device.address}", e)
            }
        }
    }

    private fun startAdvertising() {
        if (!hasBlePermissions() || isAdvertising) return

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addServiceUuid(ParcelUuid(CUSTOM_SERVICE_UUID))
            .build()

        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            // TODO: Consider calling
            //    ActivityCompat#requestPermissions
            // here to request the missing permissions, and then overriding
            //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
            //                                          int[] grantResults)
            // to handle the case where the user grants the permission. See the documentation
            // for ActivityCompat#requestPermissions for more details.
            return
        }
        advertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    private fun startGattServer() {
        if (!hasBlePermissions() || isGattServerStarted) return

        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            // TODO: Consider calling
            //    ActivityCompat#requestPermissions
            // here to request the missing permissions, and then overriding
            //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
            //                                          int[] grantResults)
            // to handle the case where the user grants the permission. See the documentation
            // for ActivityCompat#requestPermissions for more details.
            return
        }
        gattServer = bluetoothManager.openGattServer(this, object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    connectedDevices.add(device)
                    Log.i(TAG, "Conectado: ${device.address}")
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    connectedDevices.remove(device)
                    Log.i(TAG, "Desconectado: ${device.address}")
                }
            }

            override fun onDescriptorWriteRequest(
                device: BluetoothDevice, requestId: Int,
                descriptor: BluetoothGattDescriptor, preparedWrite: Boolean,
                responseNeeded: Boolean, offset: Int, value: ByteArray?
            ) {
                descriptor.value = value
                if (responseNeeded) {
                    if (ActivityCompat.checkSelfPermission(
                            this@MainActivity,
                            Manifest.permission.BLUETOOTH_CONNECT
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        // TODO: Consider calling
                        //    ActivityCompat#requestPermissions
                        // here to request the missing permissions, and then overriding
                        //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
                        //                                          int[] grantResults)
                        // to handle the case where the user grants the permission. See the documentation
                        // for ActivityCompat#requestPermissions for more details.
                        return
                    }
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                }
            }
        })

        val service = BluetoothGattService(CUSTOM_SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        val characteristic = BluetoothGattCharacteristic(
            CUSTOM_CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

        val descriptor = BluetoothGattDescriptor(
            CLIENT_CHARACTERISTIC_CONFIG_UUID,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
        )
        descriptor.value = BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE

        characteristic.addDescriptor(descriptor)
        service.addCharacteristic(characteristic)
        gattServer?.addService(service)

        isGattServerStarted = true
    }

    private fun hasBlePermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else true
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    @SuppressLint("MissingPermission")
    override fun onPause() {
        super.onPause()
        if (isSensorRegistered) {
            sensorManager.unregisterListener(this)
            isSensorRegistered = false
        }

        advertiser?.stopAdvertising(advertiseCallback)
        isAdvertising = false

        gattServer?.close()
        isGattServerStarted = false

        sendJob?.cancel()
        isSendingLoopRunning = false
    }

    override fun onResume() {
        super.onResume()
        registerSensor()
        startAdvertising()
        startGattServer()
        startSendingLoop()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isSensorRegistered) {
            sensorManager.unregisterListener(this)
            isSensorRegistered = false
        }

        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            // TODO: Consider calling
            //    ActivityCompat#requestPermissions
            // here to request the missing permissions, and then overriding
            //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
            //                                          int[] grantResults)
            // to handle the case where the user grants the permission. See the documentation
            // for ActivityCompat#requestPermissions for more details.
            return
        }
        advertiser?.stopAdvertising(advertiseCallback)
        isAdvertising = false

        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            // TODO: Consider calling
            //    ActivityCompat#requestPermissions
            // here to request the missing permissions, and then overriding
            //   public void onRequestPermissionsResult(int requestCode, String[] permissions,
            //                                          int[] grantResults)
            // to handle the case where the user grants the permission. See the documentation
            // for ActivityCompat#requestPermissions for more details.
            return
        }
        gattServer?.close()
        isGattServerStarted = false

        sendJob?.cancel()
        isSendingLoopRunning = false
    }

    @Composable
    fun MainScreen(heartRate: Float) {
        Surface(modifier = Modifier.fillMaxSize(), color = Color.Black) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                // Ícone do coração acima dos BPMs
                Image(
                    painter = painterResource(id = R.drawable.heartbox),
                    contentDescription = "Ícone grupo",
                    modifier = Modifier
                        .size(50.dp)
                        .padding(bottom = 10.dp)
                )

                // BPM, bpm
                Text(
                    text = if (heartRate > 0) "${heartRate.toInt()}" else "--",
                    fontSize = 50.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF6650A4),
                    textAlign = TextAlign.Center
                )

                // BPM texto
                Text(
                    text = "bpm",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF6650A4),
                    textAlign = TextAlign.Center
                )





            }
        }
    }
}