#include <Arduino.h>
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "RTClib.h"
#include <WiFi.h>
#include <PubSubClient.h>      
#include "esp_camera.h"
#include "soc/soc.h"           
#include "soc/rtc_cntl_reg.h"  
#include <Adafruit_MLX90640.h> 
#include <Preferences.h>

Preferences preferences;

// Configuração da câmera ESP32-CAM
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

#define I2C_DATA_PIN 14
#define I2C_CLOCK_PIN 15
#define I2C_CLOCK_SPEED 100000 
#define I2C_TIMEOUT 1000        

// UUIDs BLE
#define SERVICE_UUID            "f4b82d49-43c2-48df-b3f5-7ba9e0231908"
#define UUID_SSID               "ab35e54e-fde4-4f83-902a-07785de547b9"
#define UUID_PASS               "c1c4b63b-bf3b-4e35-9077-d5426226c710"
#define UUID_SERVERIP           "0c954d7e-9249-456d-b949-cc079205d393"
#define SENSOR_UUID             "b07d5e84-4d21-4d4a-8694-5ed9f6aa2aee" 
#define SENSOR_DATA1_UUID       "89aa9a0d-48c4-4c32-9854-e3c7f44ec091" 
#define SENSOR_DATA2_UUID       "a430a2ed-0a76-4418-a5ad-4964699ba17c" 
#define SENSOR_DATA3_UUID       "853f9ba1-94aa-4124-92ff-5a8f576767e4" 
#define CONFIG_TIME_UUID        "ca68ebcd-a0e5-4174-896d-15ba005b668e" 
#define CONFIG_ID_UUID          "eee66a40-0189-4dff-9310-b5736f86ee9c" 
#define CONFIG_FREQ_UUID        "e742e008-0366-4ec2-b815-98b814112ddc" 

// Ponteiros BLE
BLEServer *server = nullptr;              
BLECharacteristic *timeChar  = nullptr;   
BLECharacteristic *data1Char;
BLECharacteristic *data2Char;
BLECharacteristic *data3Char;

#define THERMAL_WIDTH 32
#define THERMAL_HEIGHT 24
#define THERMAL_ARRAY_SIZE THERMAL_WIDTH * THERMAL_HEIGHT

#define I2C_RETRY_COUNT 3
#define I2C_POWER_STABILIZE_DELAY 50
#define MAX_MLX_RETRIES 3
#define MLX_RETRY_DELAY 100

#define MIN_VALID_TIMESTAMP 1600000000
#define SETTING 0
#define RUNNING_BLE 1
#define RUNNING_WIFI 2

int mode = RUNNING_BLE;
String sensorID = "TC";

RTC_DS3231 rtc;             
WiFiClient espClient;         
PubSubClient mqttClient(espClient); 
Adafruit_MLX90640 mlx;      

String ssid = "";
String password = "";
char server_ip[40] = "";            
uint16_t serverPort = 1883; 

unsigned long lastSendTime = 0;     
const int sendInterval = 500;       
int delay_millis = 500;             

unsigned long lastReconnectAttempt = 0;
int reconnectInterval = 1000;       
const int maxReconnectInterval = 30000; 

float frameTemp[32*24];            
float avgTemp, minTemp, maxTemp;

bool pendingRestart = false;
unsigned long restartTimer = 0;

void print_formated_date(DateTime dt);
int setup_rtc();
void startBluetoothMode();
int setup_sensor();
bool setup_camera();
bool setup_wifi();
int get_sensor_data();
bool isValidIP(const char* ip);
void setup_mqtt();
void reconnect_mqtt();
void send_data();

class serverCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) {
    Serial.println("[BLE] Cliente conectado");
    server->getAdvertising()->stop();  
  }
  void onDisconnect(BLEServer *server) { 
    Serial.println("[BLE] Cliente desconectado. Reiniciando advertising.");
    server->getAdvertising()->start();   
  }
};

class TimeCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String value = pChar->getValue();
    if (mode == SETTING) {
      String raw = value;
      raw.trim();  
      uint32_t timestamp = strtoul(raw.c_str(), NULL, 10);  
      if (timestamp > MIN_VALID_TIMESTAMP) {
        DateTime dt(timestamp);
        rtc.adjust(dt);
      }
    }
  }
};

class IdCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String value = pChar->getValue();
    Serial.println("[BLE] Id recebido: " + value);
  }
};

class FreqCallback : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) override {
    String raw = pChar->getValue();
    raw.trim();
    uint32_t val = strtoul(raw.c_str(), NULL, 10);
    if (val >= 200 && val <= 2000) {
      delay_millis = val;
    }
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
          String value = received;
          String ip = "";
          int colonPos = value.indexOf(':');
          
          if (colonPos != -1) {
            ip = value.substring(0, colonPos);
            strncpy(server_ip, ip.c_str(), sizeof(server_ip) - 1);
          } else {
            strncpy(server_ip, value.c_str(), sizeof(server_ip) - 1);
          }
          server_ip[sizeof(server_ip) - 1] = '\0';
          serverPort = 1883;

          preferences.remove("server_ip");
          preferences.putString("server_ip", String(server_ip));
          preferences.remove("server_port");
          preferences.putInt("server_port", serverPort);
          Serial.println("🌐 [BLE] IP Recebido: " + String(server_ip));
          
          preferences.end();
          
          Serial.println("\n🚀 DADOS RECEBIDOS. A reiniciar em 5 segundos para aplicar...");
          pendingRestart = true;
          restartTimer = millis();
        }
        
        if(uuid != UUID_SERVERIP) {
            preferences.end();
        }
      }
    }
};

void startBluetoothMode() {
  Serial.println("\n--- MODO CONFIGURAÇÃO ATIVO ---");
  Serial.println("Nome: THERMAL_CAM-Heart_Box");

  BLEDevice::init("THERMAL_CAM-Heart_Box"); 
  server = BLEDevice::createServer();
  server->setCallbacks(new serverCallbacks());
  
  BLEService *pService = server->createService(SERVICE_UUID);

  BLECharacteristic *pSsidChar = pService->createCharacteristic(UUID_SSID, BLECharacteristic::PROPERTY_WRITE);
  pSsidChar->setCallbacks(new MyCallbacks());

  BLECharacteristic *pPassChar = pService->createCharacteristic(UUID_PASS, BLECharacteristic::PROPERTY_WRITE);
  pPassChar->setCallbacks(new MyCallbacks());

  BLECharacteristic *pIpChar = pService->createCharacteristic(UUID_SERVERIP, BLECharacteristic::PROPERTY_WRITE);
  pIpChar->setCallbacks(new MyCallbacks());

  pService->start();
  server->getAdvertising()->addServiceUUID(SERVICE_UUID);
  server->getAdvertising()->start();

  while (true) {
    if (pendingRestart && millis() - restartTimer > 5000) {
      ESP.restart();
    }
    Serial.print("."); 
    delay(1000);
  }
}

void print_formated_date(DateTime dt) {
  Serial.printf("%04d/%02d/%02d %02d:%02d:%02d\n", dt.year(), dt.month(), dt.day(), dt.hour(), dt.minute(), dt.second());
}

bool isValidIP(const char* ip) {
  int dots = 0; int num = 0;
  for (int i = 0; ip[i] != '\0'; i++) {
    char c = ip[i];
    if (c == '.') {
      if (dots == 3) return false; 
      dots++; if (num < 0 || num > 255) return false; num = 0;
    } else if (c >= '0' && c <= '9') {
      num = num * 10 + (c - '0'); if (num > 255) return false;
    } else return false; 
  }
  return (dots == 3 && num >= 0 && num <= 255);
}

bool setup_camera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0; config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM; config.pin_d1 = Y3_GPIO_NUM; config.pin_d2 = Y4_GPIO_NUM; config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM; config.pin_d5 = Y7_GPIO_NUM; config.pin_d6 = Y8_GPIO_NUM; config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM; config.pin_pclk = PCLK_GPIO_NUM; config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM; config.pin_sscb_sda = SIOD_GPIO_NUM; config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM; config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000; config.pixel_format = PIXFORMAT_JPEG;
  
  config.frame_size = FRAMESIZE_CIF; 
  config.jpeg_quality = 15; 
  config.fb_count = 1;
  return true;
}

int setup_rtc() {
  while(!rtc.begin()) { delay(20); }
  return 1;
}

void setup_ble() {
  BLEDevice::init("THERMAL_CAM-Heart_Box");
  server = BLEDevice::createServer();
  server->setCallbacks(new serverCallbacks());

  BLEService *configService = server->createService(SERVICE_UUID);
  timeChar = configService->createCharacteristic(CONFIG_TIME_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ);
  BLECharacteristic *idChar   = configService->createCharacteristic(CONFIG_ID_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ);
  BLECharacteristic *freqChar   = configService->createCharacteristic(CONFIG_FREQ_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ);
  BLECharacteristic *ssidChar   = configService->createCharacteristic(UUID_SSID, BLECharacteristic::PROPERTY_WRITE);
  BLECharacteristic *passChar   = configService->createCharacteristic(UUID_PASS, BLECharacteristic::PROPERTY_WRITE);
  BLECharacteristic *ipChar   = configService->createCharacteristic(UUID_SERVERIP, BLECharacteristic::PROPERTY_WRITE);

  timeChar->setCallbacks(new TimeCallback());
  idChar->setCallbacks(new IdCallback());
  freqChar->setCallbacks(new FreqCallback());
  
  MyCallbacks *wifiCallbacks = new MyCallbacks();
  ssidChar->setCallbacks(wifiCallbacks);
  passChar->setCallbacks(wifiCallbacks);
  ipChar->setCallbacks(wifiCallbacks);

  configService->start();
  
  BLEService *sensorService = server->createService(SENSOR_UUID);
  data1Char = sensorService->createCharacteristic(SENSOR_DATA1_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  data1Char->addDescriptor(new BLE2902());
  data2Char = sensorService->createCharacteristic(SENSOR_DATA2_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  data2Char->addDescriptor(new BLE2902());
  data3Char = sensorService->createCharacteristic(SENSOR_DATA3_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  data3Char->addDescriptor(new BLE2902());
  sensorService->start();

  server->getAdvertising()->addServiceUUID(SERVICE_UUID); 
  server->getAdvertising()->start(); 
  Serial.println("[BLE] Serviços CONFIG BLE iniciados.");
}

bool setup_wifi() {
  if (ssid == "" || ssid.length() < 2) {
    Serial.println("\n❌ Memória vazia.");
    startBluetoothMode();
  }

  Serial.println("[WIFI] Conectando à rede: " + String(ssid));
  WiFi.disconnect(true);  
  WiFi.mode(WIFI_STA);    
  delay(1000);            

  Wire.end();
  delay(100);
  pinMode(I2C_DATA_PIN, INPUT_PULLUP);
  pinMode(I2C_CLOCK_PIN, INPUT_PULLUP);
  delay(50);
  Wire.begin(I2C_DATA_PIN, I2C_CLOCK_PIN);
  Wire.setClock(50000); 
  
  WiFi.begin(ssid.c_str(), password.c_str());
  
  int attempts = 0;
  const int max_attempts = 30; 
  
  Serial.print("[WIFI] Tentando conectar");
  while (WiFi.status() != WL_CONNECTED && attempts < max_attempts) {
    delay(1000);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WIFI] Conectado!");
    return true;
  } else {
    Serial.println("\n[WIFI] FALHA NA CONEXÃO!");
    startBluetoothMode();
    return false;
  }
}

void setup_mqtt() {
  if (WiFi.status() != WL_CONNECTED) return;
  Serial.println("[MQTT] Configurando broker em: " + String(server_ip));
  mqttClient.setServer(server_ip, 1883);
  mqttClient.setBufferSize(4096); 
}

void reconnect_mqtt() {
  if (!mqttClient.connected()) {
    Serial.println("[MQTT] Tentando reconectar...");
    String clientId = "ESPCAM-HeartBox-" + String(random(0xffff), HEX);
    if (mqttClient.connect(clientId.c_str())) {
      Serial.println("[MQTT] Conectado ao servidor!");
    }
  }
}

int setup_sensor() {
  Wire.setClock(50000); 
  if (!mlx.begin(MLX90640_I2CADDR_DEFAULT, &Wire)) {
    while (1) delay(10); 
  }
  mlx.setMode(MLX90640_CHESS);
  mlx.setResolution(MLX90640_ADC_18BIT);
  mlx.setRefreshRate(MLX90640_2_HZ);
  return 1;
}

int get_sensor_data() {
  static unsigned long lastSuccessTime = 0;
  static int consecutiveErrors = 0;
  bool success = false;
  float sumTemp = 0;
  bool hasInvalidData = false;
  int validPixels = THERMAL_WIDTH * THERMAL_HEIGHT;

  if (consecutiveErrors >= 5) {
      if (setup_sensor()) { consecutiveErrors = 0; } 
      else { return 0; }
  }
    
  int retryCount = 0;
  while (retryCount < MAX_MLX_RETRIES && !success) {
    if (retryCount >= 2) {
      mlx.begin(MLX90640_I2CADDR_DEFAULT, &Wire);
      mlx.setMode(MLX90640_CHESS);
      mlx.setResolution(MLX90640_ADC_18BIT);
      mlx.setRefreshRate(MLX90640_1_HZ); 
      Wire.setClock(50000); 
      delay(100);
    }
      
    unsigned long startTime = millis();
    while (millis() - startTime < 1000) {  
      if (mlx.getFrame(frameTemp) == 0) {
        success = true;
        break;
      }
      delay(10);
    }
    if (!success) { delay(MLX_RETRY_DELAY * (retryCount + 1)); }
    retryCount++;
  }
  
  if (!success) {
    consecutiveErrors++;
    return 0;
  }
  
  consecutiveErrors = 0;
  lastSuccessTime = millis();
  
  minTemp = frameTemp[0];
  maxTemp = frameTemp[0];
  sumTemp = 0;
  
  for (uint8_t h = 0; h < THERMAL_HEIGHT; h++) {
    for (uint8_t w = 0; w < THERMAL_WIDTH; w++) {
      float t = frameTemp[h * THERMAL_WIDTH + w];
      
      if (t < -40.0f || t > 300.0f) {
        hasInvalidData = true;
        t = -999.0f;  
      }
      
      sumTemp += t;
      if (t < minTemp && t != -999.0f) minTemp = t;
      if (t > maxTemp && t != -999.0f) maxTemp = t;
    }
  }
  
  if (hasInvalidData) {
    validPixels = 0;
    sumTemp = 0;
    for (int i = 0; i < THERMAL_WIDTH * THERMAL_HEIGHT; i++) {
      if (frameTemp[i] != -999.0f) {
        sumTemp += frameTemp[i];
        validPixels++;
      }
    }
  }
  
  avgTemp = (validPixels > 0) ? (sumTemp / validPixels) : -999.0f;
  return (validPixels > 0) ? 1 : 0;
}

void send_data() {
  if (!mqttClient.connected()) return;
   
  int success = get_sensor_data();
  if (!success) return;

  if (maxTemp != -999.0f) {
    mqttClient.publish("heartbox/sensor/thermal", String(maxTemp).c_str());
  }
  
  mqttClient.publish("heartbox/cam/thermal_raw", (uint8_t*)frameTemp, sizeof(frameTemp));
}
int running_ble() {
  int success = get_sensor_data();
  if (success) { 
    uint32_t timestamp = rtc.now().unixtime();
    String ts = String(timestamp)+String(millis()%1000);
    String payload;

    if (avgTemp == -999.0) { payload = sensorID + ts + ".ERR"; } 
    else { payload = sensorID + ts + '.' + String((int)(avgTemp*100)); }
    if(data1Char) { data1Char->setValue(payload.c_str()); data1Char->notify(); }

    if (maxTemp == -999.0) { payload = sensorID + ts + ".ERR"; } 
    else { payload = sensorID + ts + '.' + String((int)(maxTemp*100)); }
    if(data2Char) { data2Char->setValue(payload.c_str()); data2Char->notify(); }

    if (minTemp == -999.0) { payload = sensorID + ts + ".ERR"; } 
    else { payload = sensorID + ts + '.' + String((int)(minTemp*100)); }
    if(data3Char) { data3Char->setValue(payload.c_str()); data3Char->notify(); }
    
    return 1;
  }
  return 0;
}

void running_wifi() {
  if (WiFi.status() != WL_CONNECTED) {
    if (setup_wifi()) {
      setup_mqtt();  
      lastReconnectAttempt = millis();
      reconnectInterval = 1000; 
    } else {
      delay(5000);
      return;  
    }
  }
  
  if (!mqttClient.connected()) {
    unsigned long currentTime = millis();
    if (currentTime - lastReconnectAttempt > reconnectInterval) {
      reconnect_mqtt();
      lastReconnectAttempt = currentTime;
      reconnectInterval = min(reconnectInterval * 2, maxReconnectInterval);
    }
  } else {
    mqttClient.loop();
    unsigned long currentTime = millis();
    if (currentTime - lastSendTime >= sendInterval) {
      send_data();
      lastSendTime = currentTime; 
    }
    reconnectInterval = 1000; 
  }
  delay(10);
}

void setup() {
   WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
   Serial.begin(115200);
   delay(100);
   
   preferences.begin("heartbox", false);
   ssid = preferences.getString("ssid", "");
   password = preferences.getString("password", "");
   String sip = preferences.getString("server_ip", "");
   serverPort = preferences.getInt("server_port", 1883);
   preferences.end();

   if (sip.length() > 0) {
     strncpy(server_ip, sip.c_str(), sizeof(server_ip) - 1);
     server_ip[sizeof(server_ip) - 1] = '\0';
   }

   Wire.end();  
   delay(100);  
   pinMode(I2C_DATA_PIN, INPUT_PULLUP);
   pinMode(I2C_CLOCK_PIN, INPUT_PULLUP);
   delay(50);  
   Wire.begin(I2C_DATA_PIN, I2C_CLOCK_PIN);
   Wire.setClock(I2C_CLOCK_SPEED);
   Wire.setTimeOut(I2C_TIMEOUT);

   setup_rtc();
   setup_sensor();
   setup_camera();
   
   if (ssid != "" && password != "" && server_ip[0] != '\0') {
      if(setup_wifi()) {
        setup_mqtt();
        mode = RUNNING_WIFI;
      }
   } else {
      setup_ble();
      mode = RUNNING_BLE;
   }
}

void loop() {
  if (mode == RUNNING_BLE) {
    running_ble();
  } else if (mode == RUNNING_WIFI) {
    running_wifi();
  } else if (mode == SETTING) {
    if(ssid != "" && password != "" && server_ip[0] != '\0') {
      if(setup_wifi()) {
        setup_mqtt();
        mode = RUNNING_WIFI;
      }
    }
  }
  
  if (pendingRestart && millis() - restartTimer > 5000) {
    ESP.restart();
  }
  
  delay(delay_millis);
}
