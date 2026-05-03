#include <TinyGPS++.h>

// Definição dos Pinos (Ligação física)
// TX do GPS -> Pino 8 (RX no ESP32)
// RX do GPS -> Pino 9 (TX no ESP32)
#define RXD2 8
#define TXD2 9

// Ajuste de Fuso Horário (Portugal Horário de Verão = +1)
const int UTC_OFFSET = 1;

// Instância do Objeto TinyGPS++
TinyGPSPlus gps;

// O ESP32-S3 tem 3 portas Serial. Usaremos a Serial2 para o GPS.
HardwareSerial gpsSerial(2);

void setup() {
  // Monitor Serial para o teu PC
  Serial.begin(115200);
  
  // Inicializa a comunicação com o GPS (O padrão do NEO-6M é 9600 baud)
  gpsSerial.begin(9600, SERIAL_8N1, RXD2, TXD2);

  Serial.println("--- Sistema GPS Inicializado ---");
  Serial.println("Aguardando fixação de satélites...");
}

void loop() {
  // Lê os dados vindos do módulo GPS
  while (gpsSerial.available() > 0) {
    if (gps.encode(gpsSerial.read())) {
      displayInfo();
    }
  }

  // Se após 5 segundos não houver dados nenhuns, avisa sobre a ligação física
  if (millis() > 5000 && gps.charsProcessed() < 10) {
    Serial.println("Erro crítico: GPS não detetado. Verifica os cabos nos pinos 8 e 9.");
    delay(5000);
  }
}

void displayInfo() {
  // --- LOCALIZAÇÃO ---
  Serial.print("Localização: "); 
  if (gps.location.isValid()) {
    Serial.print(gps.location.lat(), 6);
    Serial.print(",");
    Serial.print(gps.location.lng(), 6);
  } else {
    Serial.print("A procurar satélites...");
  }

  // --- DATA ---
  Serial.print(" | Data: ");
  if (gps.date.isValid()) {
    Serial.print(gps.date.day());
    Serial.print("/");
    Serial.print(gps.date.month());
    Serial.print("/");
    Serial.print(gps.date.year());
  } else {
    Serial.print("Aguardando...");
  }

  // --- HORA (Com ajuste de fuso horário) ---
  Serial.print(" | Hora: ");
  if (gps.time.isValid()) {
    int hour = gps.time.hour() + UTC_OFFSET;
    
    // Ajuste simples para viragem do dia
    if (hour >= 24) hour -= 24;
    if (hour < 0) hour += 24;

    if (hour < 10) Serial.print(F("0"));
    Serial.print(hour);
    Serial.print(F(":"));
    if (gps.time.minute() < 10) Serial.print(F("0"));
    Serial.print(gps.time.minute());
    Serial.print(F(":"));
    if (gps.time.second() < 10) Serial.print(F("0"));
    Serial.print(gps.time.second());
  } else {
    Serial.print("Aguardando...");
  }

  Serial.println();
}