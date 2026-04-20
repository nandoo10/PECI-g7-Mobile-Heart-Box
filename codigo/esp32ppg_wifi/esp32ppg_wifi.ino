#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>

// ===== CONFIGURAÇÃO WIFI =====
const char* ssid = "iPhone de Jorge";
const char* password = "jorginho6";

// ===== CONFIGURAÇÃO MQTT =====
const char* mqtt_server = "172.20.10.8";
const int mqtt_port = 1883;
const char* mqtt_user = "esp32";
const char* mqtt_pass = "ppg123";
const char* mqtt_topic = "sensor/ppg";

WiFiClient espClient;
PubSubClient client(espClient);

// ===== CONFIGURAÇÃO SENSOR =====
#define HEARTRATE_PIN 5
const int SAMPLE_INTERVAL = 20; // Amostragem a 50Hz (estável para BPM)

// Variáveis de Processamento
float signalFiltered = 2000;    // Começa num valor médio do ADC do ESP32
bool beatDetected = false;
unsigned long lastBeatTime = 0;
unsigned long lastSampleTime = 0;
int bpm = 0;

void setup_wifi() {
  Serial.print("[WiFi] Conectando...");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\n[WiFi] Conectado!");
}

void reconnect_mqtt() {
  while (!client.connected()) {
    Serial.print("[MQTT] Tentando ligar...");
    if (client.connect("ESP32_PPG", mqtt_user, mqtt_pass)) {
      Serial.println("Conectado!");
    } else {
      Serial.print("Falha, rc=");
      Serial.print(client.state());
      Serial.println(" - Retentando em 5s");
      delay(5000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(HEARTRATE_PIN, INPUT);
  setup_wifi();
  client.setServer(mqtt_server, mqtt_port);
  Serial.println("\n[SISTEMA] Monitorização iniciada.");
}

void loop() {
  if (!client.connected()) reconnect_mqtt();
  client.loop();

  // Garante que a leitura é feita em intervalos regulares (essencial para sinais biológicos)
  if (millis() - lastSampleTime >= SAMPLE_INTERVAL) {
    lastSampleTime = millis();
    
    int rawValue = analogRead(HEARTRATE_PIN);

    // FILTRO DINÂMICO: O sinal filtrado segue a tendência lenta do sinal (a média)
    // 0.98 mantém a base estável, 0.02 absorve as mudanças lentas
    signalFiltered = (signalFiltered * 0.98) + (rawValue * 0.02);

    // DETECÇÃO DE PICO (BATIMENTO)
    // Se o valor atual subir 80 unidades acima da média (ajusta este '80' se necessário)
    if (rawValue > (signalFiltered + 80) && !beatDetected) {
      unsigned long now = millis();
      unsigned long interval = now - lastBeatTime;

      // Filtro de intervalo: 400ms (150 BPM) a 1500ms (40 BPM)
      if (interval > 400 && interval < 1500) {
        bpm = 60000 / interval;
        
        // Output para Monitor/Plotter
        Serial.print("BPM:"); Serial.println(bpm);

        // Envio MQTT
        String payload = String(bpm);
        client.publish(mqtt_topic, payload.c_str());
      }
      
      lastBeatTime = now;
      beatDetected = true;
    }

    // RESET DA DETECÇÃO
    // Permite detetar a próxima batida quando o sinal cai abaixo da média
    if (rawValue < signalFiltered) {
      beatDetected = false;
    }
  }
}