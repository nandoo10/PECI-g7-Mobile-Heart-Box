#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <math.h>
#include <TinyGPS++.h>
#include "Waveshare_10Dof-D.h"
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

Preferences preferences;
String ssid = "";
String password = "";
String mqtt_server = ""; 

#define SERVICE_UUID        "0a3b6985-dad6-4759-8852-dcb266d3a59e"
#define UUID_SSID           "ab35e54e-fde4-4f83-902a-07785de547b9"
#define UUID_PASS           "c1c4b63b-bf3b-4e35-9077-d5426226c710"
#define UUID_SERVERIP       "0c954d7e-9249-456d-b949-cc079205d393"

const char* topic_gps     = "heartbox/gps/coords";
const char* topic_fall    = "heartbox/alerts/fall";
const char* topic_bpm     = "heartbox/heart/bpm";

WiFiClient espClient;
PubSubClient client(espClient);

#define SDA_PIN 20
#define SCL_PIN 21
#define RXD2 8
#define TXD2 9
#define LO_PLUS  3
#define LO_MINUS 2
#define ECG_PIN  1

TinyGPSPlus gps;
HardwareSerial gpsSerial(2);

// Temporizadores MQTT e Envio
unsigned long lastMsgTime      = 0;
unsigned long lastBpmSendTime  = 0;
const unsigned long interval   = 2000;
const unsigned long bpmSendInterval = 5000; 
bool fallDetected = false;

int           threshold        = 2000;
int           ecgPrev          = 0;
int           ecgPeak          = 0;
bool          rising           = false;
bool          inPeak           = false;
unsigned long peakTime         = 0;

unsigned long beat_old         = 0;
const unsigned long REFRACTORY = 400;  // 400ms → máx 150 BPM fisiológico

float         rrIntervals[8]   = {0};
int           rrIndex          = 0;
int           rrCount          = 0;
int           bpm              = 0;

const float FALL_ANGLE_THRESHOLD = 60.0;

// Variáveis de Controlo de Estados
#define SETTING 0
#define RUNNING_BLE 1
#define RUNNING_WIFI 2
int mode = RUNNING_BLE;

unsigned long lastReconnectAttempt = 0;
int reconnectInterval = 1000;
const int maxReconnectInterval = 30000;

bool pendingRestart = false;
unsigned long restartTimer = 0;

// Classes de Callbacks BLE

class serverCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    Serial.println("[BLE] App Conectada à S3");
  }
  void onDisconnect(BLEServer *pServer) {
    Serial.println("[BLE] App Desconectada. A reiniciar advertising.");
    pServer->getAdvertising()->start();
  }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String received = pCharacteristic->getValue();
      String uuid = String(pCharacteristic->getUUID().toString().c_str());
      
      if (received.length() > 0) {
        preferences.begin("heartbox", false); 

        if (uuid == UUID_SSID) {
          preferences.remove("ssid");
          preferences.putString("ssid", received);
          Serial.println("📶 [BLE] SSID Novo: " + received);
        } 
        else if (uuid == UUID_PASS) {
          preferences.remove("password");
          preferences.putString("password", received);
          Serial.println("🔑 [BLE] Password recebida!");
        } 
        else if (uuid == UUID_SERVERIP) {
          preferences.remove("mqtt_server");
          preferences.putString("mqtt_server", received);
          Serial.println("🌐 [BLE] IP Recebido: " + received);
          
          preferences.end();
          Serial.println("\n🚀 DADOS RECEBIDOS. A reiniciar em 5 segundos...");
          pendingRestart = true;
          restartTimer = millis();
        }
        
        if(uuid != UUID_SERVERIP) {
            preferences.end();
        }
      }
    }
};

// Funções de Setup (WIFI, MQTT, BLE)

void setup_ble() {
  Serial.println("\n--- A INICIAR SERVIÇOS BLE ---");
  Serial.println("Nome: ESP32_S3-Heart_Box");

  BLEDevice::init("ESP32_S3-Heart_Box"); 
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new serverCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic *pSsidChar = pService->createCharacteristic(UUID_SSID, BLECharacteristic::PROPERTY_WRITE);
  pSsidChar->setCallbacks(new MyCallbacks());

  BLECharacteristic *pPassChar = pService->createCharacteristic(UUID_PASS, BLECharacteristic::PROPERTY_WRITE);
  pPassChar->setCallbacks(new MyCallbacks());

  BLECharacteristic *pIpChar = pService->createCharacteristic(UUID_SERVERIP, BLECharacteristic::PROPERTY_WRITE);
  pIpChar->setCallbacks(new MyCallbacks());

  pService->start();
  pServer->getAdvertising()->addServiceUUID(SERVICE_UUID);
  pServer->getAdvertising()->start();
  Serial.println("[BLE] S3 a escutar configurações em segundo plano.");
}

bool setup_wifi() {
  if (ssid == "" || ssid == "NULL" || ssid.length() < 2) {
    Serial.println("\n❌ Credenciais Wi-Fi não encontradas.");
    return false;
  }

  Serial.println("\n[WIFI] Tentando ligar a: " + ssid);
  WiFi.disconnect(true);
  delay(1000);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());

  int attempt = 0;
  const int max_attempts = 30; 
  
  while (WiFi.status() != WL_CONNECTED && attempt < max_attempts) {
    delay(1000);
    Serial.print(".");
    attempt++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ [WIFI] Conectado com sucesso!");
    return true;
  } else {
    Serial.println("\n❌ [WIFI] FALHA NA CONEXÃO!");
    return false;
  }
}

void setup_mqtt() {
  if (WiFi.status() != WL_CONNECTED) return;
  
  String ip_only = mqtt_server;
  int colonIndex = mqtt_server.indexOf(':');
  if (colonIndex != -1) {
    ip_only = mqtt_server.substring(0, colonIndex);
  }
  
  Serial.println("[MQTT] Configurando: " + ip_only + ":1883");
  client.setServer(ip_only.c_str(), 1883);
  client.setBufferSize(2048); 
  client.setKeepAlive(15);
}

void reconnect_mqtt() {
  if (!client.connected()) {
    Serial.println("[MQTT] Tentando reconectar...");
    const char* clientId = "ESP32_S3_HEARTBOX";
    if (client.connect(clientId, NULL, NULL, NULL, 0, 0, NULL, true)) { 
      Serial.println("✅ [MQTT] Conectado ao servidor!"); 
      reconnectInterval = 1000;
    } else {
      Serial.print("❌ [MQTT] Falha, estado: ");
      Serial.println(client.state());
    }
  }
}

// Processamento de Sensores

void calculateBPM() {
  unsigned long now = millis();
  unsigned long rr  = now - beat_old;

  // Ignora tudo abaixo de 400ms, porque 150 BPM não é realista em repouso
  if (rr < REFRACTORY) return;

  // Se passou mais de 2.5s, o sinal perdeu-se, reinicia
  if (rr > 2500) {
    beat_old = now;
    return;
  }

  beat_old = now;

  rrIntervals[rrIndex] = (float)rr;
  rrIndex = (rrIndex + 1) % 8;
  if (rrCount < 8) rrCount++;

  // Ignora as primeira 4 amostras por causa de picos que não são realistas
  if (rrCount < 4) return;

  float sorted[8];
  int n = rrCount;
  for (int i = 0; i < n; i++) sorted[i] = rrIntervals[i];
  
  for (int i = 0; i < n - 1; i++)
    for (int j = 0; j < n - i - 1; j++)
      if (sorted[j] > sorted[j+1]) {
        float tmp = sorted[j]; sorted[j] = sorted[j+1]; sorted[j+1] = tmp;
      }

  // Mediana
  float medianRR;
  if (n % 2 == 0)
    medianRR = (sorted[n/2 - 1] + sorted[n/2]) / 2.0;
  else
    medianRR = sorted[n/2];

  // Descarta intervalos muito afastados da mediana (> 25% de desvio)
  float total = 0;
  int valid   = 0;
  for (int i = 0; i < n; i++) {
    if (abs(rrIntervals[i] - medianRR) / medianRR < 0.25) {
      total += rrIntervals[i];
      valid++;
    }
  }

  if (valid >= 2) {
    float avgRR = total / valid;
    int newBpm  = (int)(60000.0 / avgRR);
    if (newBpm >= 45 && newBpm <= 150) {
      bpm = newBpm;
    }
  }
}

void process_sensors() {
  // Processar GPS
  while (gpsSerial.available() > 0) gps.encode(gpsSerial.read());

  // Processar Quedas
  IMU_ST_ANGLES_DATA stAngles; IMU_ST_SENSOR_DATA stGyro, stAccel, stMagn;
  imuDataGet(&stAngles, &stGyro, &stAccel, &stMagn);
  if (abs(stAngles.fRoll) > FALL_ANGLE_THRESHOLD || abs(stAngles.fPitch) > FALL_ANGLE_THRESHOLD) {
    if (!fallDetected) {
      fallDetected = true;
      if (client.connected()) client.publish(topic_fall, "ALERTA: Queda detetada");
    }
  } else {
    fallDetected = false;
  }

  // ECG 
  if ((digitalRead(LO_PLUS) == 0) && (digitalRead(LO_MINUS) == 0)) {
    int ecgValue = analogRead(ECG_PIN);

    // Deteção de subida
    if (ecgValue > ecgPrev) {
      rising  = true;
      ecgPeak = max(ecgPeak, ecgValue);
    }

    // Pico detetado: estava a subir e agora desceu
    if (rising && ecgValue < ecgPrev) {
      // Só processa se o pico ultrapassou o threshold (filtra ruído de base)
      if (ecgPeak > threshold && !inPeak) {
        inPeak = true;
        calculateBPM();
      }
      rising  = false;
      ecgPeak = 0;
    }

    if (ecgValue < threshold - 200) {
      inPeak = false;
    }

    ecgPrev = ecgValue;

    // Envio MQTT a cada 5s
    unsigned long currentMillis = millis();
    if (client.connected() && (currentMillis - lastBpmSendTime >= bpmSendInterval)) {
      if (bpm >= 45 && bpm <= 150) {
        client.publish(topic_bpm, String(bpm).c_str());
        lastBpmSendTime = currentMillis;
      }
    }

  } else {
    // Elétrodos soltos vai limpar tudo
    if (bpm != 0) {
      bpm     = 0;
      rrCount = 0;
      rrIndex = 0;
      for (int i = 0; i < 8; i++) rrIntervals[i] = 0;
      ecgPrev = 0; ecgPeak = 0; rising = false; inPeak = false;
      if (client.connected()) client.publish(topic_bpm, "!");
    }
  }
}

// Máquina de Estados

void running_ble() {
  process_sensors();
}

void running_wifi() {
  process_sensors();

  if (WiFi.status() != WL_CONNECTED) {
    if (setup_wifi()) {
      setup_mqtt();  
      lastReconnectAttempt = millis();
      reconnectInterval = 1000; 
    } else {
      mode = RUNNING_BLE;
      return;  
    }
  }
  
  if (!client.connected()) {
    unsigned long currentTime = millis();
    if (currentTime - lastReconnectAttempt > reconnectInterval) {
      reconnect_mqtt();
      lastReconnectAttempt = currentTime;
      reconnectInterval = min(reconnectInterval * 2, maxReconnectInterval);
    }
  } else {
    client.loop();
    reconnectInterval = 1000;

    unsigned long currentTime = millis();
    
    if (currentTime - lastMsgTime >= interval) {
      lastMsgTime = currentTime;
      String payload = gps.location.isValid() ? String(gps.location.lat(), 6) + "," + String(gps.location.lng(), 6) : "Sem sinal GPS";
      client.publish(topic_gps, payload.c_str());
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  preferences.begin("heartbox", false);
  ssid = preferences.getString("ssid", "");
  password = preferences.getString("password", "");
  mqtt_server = preferences.getString("mqtt_server", "");
  preferences.end(); 
  
  gpsSerial.begin(9600, SERIAL_8N1, RXD2, TXD2);
  Wire.begin(SDA_PIN, SCL_PIN);
  IMU_EN_SENSOR_TYPE enMotionSensorType, enPressureType;
  imuInit(&enMotionSensorType, &enPressureType);
  pinMode(LO_PLUS, INPUT);
  pinMode(LO_MINUS, INPUT);
  
  setup_ble();
  
  if (ssid != "" && password != "" && mqtt_server != "") {
    if (setup_wifi()) {
      String ip_only = mqtt_server;
      int colonIndex = mqtt_server.indexOf(':');
      if (colonIndex != -1) ip_only = mqtt_server.substring(0, colonIndex);
      
      WiFiClient testClient;
      if (testClient.connect(ip_only.c_str(), 1883)) {
        testClient.stop();
        setup_mqtt();
        mode = RUNNING_WIFI;
      } else {
        setup_mqtt();
        mode = RUNNING_WIFI;
      }
    } else {
      mode = RUNNING_BLE;
    }
  } else {
    mode = RUNNING_BLE;
  }
}

void loop() {
  if (mode == RUNNING_BLE) {
    running_ble();
  } else if (mode == RUNNING_WIFI) {
    running_wifi();
  } else if (mode == SETTING) {
    if (ssid != "" && password != "" && mqtt_server != "") {
      if (setup_wifi()) {
        setup_mqtt();
        mode = RUNNING_WIFI;
      } else {
        mode = RUNNING_BLE;
      }
    }
  }
  
  if (pendingRestart && millis() - restartTimer > 5000) {
    ESP.restart();
  }
  
  delay(10);
}
