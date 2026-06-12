#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

Preferences preferences;
String ssid = "";
String password = "";
String mqtt_server = "";

#define SERVICE_UUID   "7e408544-2ab3-4581-b541-1188318e8df5"
#define UUID_SSID      "ab35e54e-fde4-4f83-902a-07785de547b9"
#define UUID_PASS      "c1c4b63b-bf3b-4e35-9077-d5426226c710"
#define UUID_SERVERIP  "0c954d7e-9249-456d-b949-cc079205d393"

WiFiClient espClient;
PubSubClient client(espClient);

// Configuração para o sensor mmWave
HardwareSerial mmWaveSerial(2);
#define RX_PIN 4
#define TX_PIN 5

bool alertaEnviado = false;
#define DISTANCIA_LIMITE 100

bool pendingRestart = false;
unsigned long restartTimer = 0;

// Callbacks BLE

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String received = pCharacteristic->getValue();
    String uuid = String(pCharacteristic->getUUID().toString().c_str());

    if (received.length() > 0) {
      preferences.begin("heartbox", false);

      if (uuid == UUID_SSID) {
        preferences.remove("ssid");
        preferences.putString("ssid", received);
        Serial.println("📶 [BLE] SSID Novo: " + received);
      } else if (uuid == UUID_PASS) {
        preferences.remove("password");
        preferences.putString("password", received);
        Serial.println("🔑 [BLE] Password recebida!");
      } else if (uuid == UUID_SERVERIP) {
        preferences.remove("mqtt_server");
        preferences.putString("mqtt_server", received);
        Serial.println("🌐 [BLE] IP Recebido: " + received);
        preferences.end();
        Serial.println("\n🚀 DADOS RECEBIDOS. A reiniciar em 5 segundos...");
        pendingRestart = true;
        restartTimer = millis();
      }

      if (uuid != UUID_SERVERIP) {
        preferences.end();
      }
    }
  }
};

void startBluetoothMode() {
  Serial.println("\n--- MODO CONFIGURAÇÃO ATIVO ---");
  Serial.println("Nome: ESP32_S3_ZERO-Heart_Box");

  BLEDevice::init("ESP32_S3_ZERO-Heart_Box");
  BLEServer *pServer = BLEDevice::createServer();
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

  while (true) {
    if (pendingRestart && millis() - restartTimer > 5000) {
      ESP.restart();
    }
    Serial.print(".");
    delay(500);
  }
}

void setup_wifi() {
  if (ssid == "" || ssid == "NULL" || ssid.length() < 2) {
    startBluetoothMode();
  }

  Serial.println("\n--- Tentando ligar a: " + ssid + " ---");
  WiFi.disconnect(true);
  delay(1000);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());

  int attempt = 0;
  while (WiFi.status() != WL_CONNECTED && attempt < 60) {
    delay(500);
    Serial.print(".");
    attempt++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ Conectado!");
  } else {
    Serial.println("\n❌ Falha persistente. Abrindo Bluetooth para novo QR...");
    startBluetoothMode();
  }
}

void reconnect() {
  while (!client.connected()) {
    if (WiFi.status() != WL_CONNECTED) {
      setup_wifi();
    }

    String ip_only = mqtt_server;
    int colonIndex = mqtt_server.indexOf(':');
    if (colonIndex != -1) ip_only = mqtt_server.substring(0, colonIndex);

    client.setServer(ip_only.c_str(), 1883);
    String clientId = "ESP32S3ZERO-HB-" + String(random(0xffff), HEX);

    Serial.print("A tentar ligação MQTT a " + ip_only + "...");
    if (client.connect(clientId.c_str())) {
      Serial.println(" ✅ MQTT OK");
    } else {
      Serial.print(" ❌ falhou, rc=");
      Serial.print(client.state());
      Serial.println(" a tentar novamente em 5 segundos...");
      delay(5000);
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

  mmWaveSerial.begin(115200, SERIAL_8N1, RX_PIN, TX_PIN);
  delay(1000);
  Serial.println("Sensor mmWave iniciado.");

  setup_wifi();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    setup_wifi();
  }
  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  // Leitura do sensor linha a linha 

  while (mmWaveSerial.available()) {
    String linha = mmWaveSerial.readStringUntil('\n');
    linha.trim();

    if (linha.startsWith("Range")) {
      int distancia = linha.substring(6).toInt();

      Serial.print("Distancia: ");
      Serial.print(distancia);
      Serial.println(" cm");

      if (distancia <= DISTANCIA_LIMITE && !alertaEnviado) {
        client.publish("heartbox/sensor/proximity", "OBSTACULO_PERTO");
        Serial.println("⚠️ MQTT: Obstáculo perto!");
        alertaEnviado = true;
      } else if (distancia > DISTANCIA_LIMITE && alertaEnviado) {
        client.publish("heartbox/sensor/proximity", "CAMINHO_LIVRE");
        Serial.println("✅ MQTT: Caminho livre.");
        alertaEnviado = false;
      }
    } else if (linha == "OFF") {
      // Sem presença
      if (alertaEnviado) {
        client.publish("heartbox/sensor/proximity", "CAMINHO_LIVRE");
        Serial.println("✅ MQTT: Caminho livre (sem presença).");
        alertaEnviado = false;
      }
    }
  }

  if (pendingRestart && millis() - restartTimer > 5000) {
    ESP.restart();
  }
}
