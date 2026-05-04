#include <Wire.h>
#include "Waveshare_10Dof-D.h"
#include <math.h>

#define SDA_PIN 20
#define SCL_PIN 21

// Limiares ajustáveis
#define ACC_THRESHOLD 20000   // impacto / movimento brusco
#define ANGLE_THRESHOLD 90.0  // mudança de ~90° em roll ou pitch

float prevRoll = 0;
float prevPitch = 0;

void setup() {
  Serial.begin(115200);
  delay(2000);

  Wire.begin(SDA_PIN, SCL_PIN);

  Serial.println("Inicializando IMU...");

  IMU_EN_SENSOR_TYPE enMotionSensorType, enPressureType;
  imuInit(&enMotionSensorType, &enPressureType);

  if (enMotionSensorType == IMU_EN_SENSOR_TYPE_ICM20948) {
    Serial.println("Motion sensor: ICM-20948 OK");
  } else {
    Serial.println("Motion sensor NÃO detetado");
  }

  if (enPressureType == IMU_EN_SENSOR_TYPE_BMP280) {
    Serial.println("Pressure sensor: BMP280 OK");
  } else {
    Serial.println("Pressure sensor NÃO detetado");
  }

  delay(1000);
}

void loop() {
  IMU_ST_ANGLES_DATA stAngles;
  IMU_ST_SENSOR_DATA stGyroRawData;
  IMU_ST_SENSOR_DATA stAccelRawData;
  IMU_ST_SENSOR_DATA stMagnRawData;

  imuDataGet(&stAngles, &stGyroRawData, &stAccelRawData, &stMagnRawData);

  // ------------------------
  // Cálculo da magnitude da aceleração
  // ------------------------
  float accX = stAccelRawData.s16X;
  float accY = stAccelRawData.s16Y;
  float accZ = stAccelRawData.s16Z;
  float accMagnitude = sqrt(accX * accX + accY * accY + accZ * accZ);

  // ------------------------
  // Mudança de orientação
  // ------------------------
  float roll = stAngles.fRoll;
  float pitch = stAngles.fPitch;

  bool movementDetected = accMagnitude > ACC_THRESHOLD;
  bool rotated90 = (abs(roll - prevRoll) > ANGLE_THRESHOLD) || (abs(pitch - prevPitch) > ANGLE_THRESHOLD);

  // ------------------------
  // OUTPUT
  // ------------------------
  Serial.println();
  Serial.println("------ IMU DATA ------");
  Serial.print("Roll: "); Serial.print(roll);
  Serial.print(" Pitch: "); Serial.print(pitch);
  Serial.print(" Yaw: "); Serial.println(stAngles.fYaw);

  Serial.print("Accel Magnitude: "); Serial.println(accMagnitude);

  if (movementDetected) {
    Serial.println("⚡ MOVIMENTO BRUSCO DETETADO!");
  }

  if (rotated90) {
    Serial.println("🔄 SENSOR RODOU 90º OU MAIS!");
  }

  Serial.println("----------------------");

  // Atualizar histórico
  prevRoll = roll;
  prevPitch = pitch;

  delay(500);
}