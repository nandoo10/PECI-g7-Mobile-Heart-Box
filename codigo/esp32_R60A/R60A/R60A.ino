#include "Arduino.h"
#include <60ghzbreathheart.h>

// Definir pinos UART
#define RX_PIN 16
#define TX_PIN 17

// Criar Serial1 com pinos definidos (ESP32-S3)
HardwareSerial RadarSerial(1);

// Inicializar sensor com a Serial correta
BreathHeart_60GHz radar = BreathHeart_60GHz(&RadarSerial);

void setup() {
  Serial.begin(115200);

  // IMPORTANTE: definir pinos no begin
  RadarSerial.begin(115200, SERIAL_8N1, RX_PIN, TX_PIN);

  delay(2000);

  Serial.println("Ready");
}

void loop()
{
  radar.HumanExis_Func();

  if (radar.sensor_report != 0x00) {

    switch (radar.sensor_report) {

      case NOONE:
        Serial.println("Nobody here.");
        break;

      case SOMEONE:
        Serial.println("Someone is here.");
        break;

      case NONEPSE:
        Serial.println("No human activity messages.");
        break;

      case STATION:
        Serial.println("Someone stop");
        break;

      case MOVE:
        Serial.println("Someone moving");
        break;

      case BODYVAL:
        Serial.print("Body sign value: ");
        Serial.println(radar.bodysign_val, DEC);
        break;

      case DISVAL:
        Serial.print("Distance: ");
        Serial.print(radar.distance, DEC);
        Serial.println(" m");
        break;

      case DIREVAL:
        Serial.print("Direction X: ");
        Serial.print(radar.Dir_x);
        Serial.print(" Y: ");
        Serial.print(radar.Dir_y);
        Serial.print(" Z: ");
        Serial.println(radar.Dir_z);
        break;
    }

    Serial.println("----------------------------");
  }

  delay(200);
}