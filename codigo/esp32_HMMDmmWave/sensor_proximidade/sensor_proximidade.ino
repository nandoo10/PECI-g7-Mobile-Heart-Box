#include <Arduino.h>

// UART2 para o sensor mmWave
HardwareSerial mmWaveSerial(2);

// Pinos para ESP32-S3 Zero
#define RX_PIN 4   // Recebe dados do sensor
#define TX_PIN 5   // Envia dados para o sensor

// Buffer para leitura dos dados binários
uint8_t buffer[64];
int indexBuffer = 0;

// Controle de estado
unsigned long lastDetectionTime = 0;
bool estadoAtual = false;

// Parâmetros
#define TIMEOUT_OFF 2000   // 2 segundos sem deteção = OFF

void setup() {
  Serial.begin(115200);

  // Inicializar UART do sensor com os pinos corretos
  mmWaveSerial.begin(115200, SERIAL_8N1, RX_PIN, TX_PIN);

  Serial.println("MMWave iniciado (ESP32-S3 Zero)");

  delay(1000); // MUITO IMPORTANTE

  // Comando para colocar sensor em REPORT MODE
  String hex_to_send = "FDFCFBFA0800120000000400000004030201";
  sendHexData(hex_to_send);

  delay(500);
}

void loop() {
  readSerialData();

  // Se ficar sem detecção durante TIMEOUT_OFF → OFF
  if (millis() - lastDetectionTime > TIMEOUT_OFF) {
    if (estadoAtual == true) {
      Serial.println("Estado: OFF");
      estadoAtual = false;
    }
  }
}

void sendHexData(String hexString) {
  int len = hexString.length();
  byte bufferSend[len / 2];

  for (int i = 0; i < len; i += 2) {
    bufferSend[i / 2] = strtoul(hexString.substring(i, i + 2).c_str(), NULL, 16);
  }

  mmWaveSerial.write(bufferSend, sizeof(bufferSend));
}

void readSerialData() {
  while (mmWaveSerial.available()) {
    uint8_t byteRead = mmWaveSerial.read();

    // Guardar byte no buffer
    buffer[indexBuffer++] = byteRead;

    // Evitar overflow
    if (indexBuffer >= 64) indexBuffer = 0;

    // Procurar header da frame: F4 F3 F2 F1
    if (indexBuffer >= 9) {
      if (buffer[0] == 0xF4 &&
          buffer[1] == 0xF3 &&
          buffer[2] == 0xF2 &&
          buffer[3] == 0xF1) {

        uint8_t detection = buffer[6];  // 0 ou 1
        uint16_t distance = buffer[7] | (buffer[8] << 8);

        // Mostrar qualquer distância detectada
        if (detection == 1) {
          lastDetectionTime = millis();

          if (!estadoAtual) {
            Serial.println("Estado: ON");
            estadoAtual = true;
          }

          Serial.print("Distância: ");
          Serial.print(distance);
          Serial.println(" cm");
        }

        // Reset buffer para próxima frame
        indexBuffer = 0;
      }
    }
  }
}