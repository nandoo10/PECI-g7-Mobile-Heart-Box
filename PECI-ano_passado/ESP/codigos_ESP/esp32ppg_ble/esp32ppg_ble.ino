#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include "DFRobot_Heartrate.h"

// ===== CONFIGURAÇÃO WIFI =====
const char* ssid = "iPhone de Jorge";          // substitui pelo nome da tua rede Wi-Fi
const char* password = "jorginho6";     // substitui pela senha da tua rede Wi-Fi

// ===== CONFIGURAÇÃO MQTT =====
const char* mqtt_server = "172.20.10.8"; // IP da máquina Linux onde corre Mosquitto
const int mqtt_port = 1883;
const char* mqtt_topic = "sensor/ppg";

WiFiClient espClient;
PubSubClient client(espClient);

// ===== SENSOR PPG =====
#define HEARTRATE_PIN 5
DFRobot_Heartrate heartrate(DIGITAL_MODE);

// ===== FUNÇÕES =====
void setup_wifi() {
  Serial.print("[WiFi] Conectando-se à rede ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n[WiFi] Conectado!");
  Serial.print("[WiFi] IP atribuído: ");
  Serial.println(WiFi.localIP());
}

void reconnect_mqtt() {
  while (!client.connected()) {
    Serial.print("[MQTT] Tentando conectar...");
    if (client.connect("ESP32_PPG")) {
      Serial.println("Conectado ao broker MQTT!");
    } else {
      Serial.print("[MQTT] Falhou, rc=");
      Serial.print(client.state());
      Serial.println(" tentando novamente em 5s");
      delay(5000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(100);

  // Inicializa Wi-Fi
  setup_wifi();

  // Inicializa MQTT
  client.setServer(mqtt_server, mqtt_port);

  // Inicializa sensor PPG
  heartrate.getValue(HEARTRATE_PIN);
  heartrate.getRate();
  Serial.println("[PPG] Sensor iniciado");
}

void loop() {
  // Assegura conexão MQTT
  if (!client.connected()) {
    reconnect_mqtt();
  }
  client.loop();

  // Lê PPG
  heartrate.getValue(HEARTRATE_PIN);
  int bpm = heartrate.getRate();

  // Se não detecta batimento, envia 0
  if (bpm > 0) {
    Serial.print("[MQTT] Enviado: ");
    Serial.println(bpm);
  } else {
    bpm = 0; // força envio 0
    Serial.println("[MQTT] Nenhum batimento detectado, enviando 0");
  }

  // Publica sempre
  String payload = String(bpm);
  client.publish(mqtt_topic, payload.c_str());

  delay(1000); // envia a cada 1 segundo
}