# PECI-G13: The Heart Box

### Final project for the Computer Engineering degree – Group 13 (University of Aveiro)

---

## Overview

The Heart Box is a modular system for real-time physiological monitoring, designed for indoor cycling sessions (spinning classes) and stationary bike training. It collects heart rate and body temperature data using PPG sensors, smartwatches, and thermal cameras. The system integrates an Android app, smartwatch app, ESP32 microcontrollers, and a cloud backend for both individual and group usage.

🔗 [Website](https://carolineribeiro19.github.io/THB) | 🎥 [Video](https://youtu.be/PlrUbAjPF5k?si=5I7KM5DKnNWRzQ09)



## Team

* [Caroline Ribeiro](https://github.com/CarolineRibeiro19)  
* [João Rodrigues](https://github.com/joaoamrodrigues)  
* [Júlia Abrantes](https://github.com/JuliaAbrantes)  
* [Mateus Fonte](https://github.com/mateus-fonte)  
* [Nicole Rakov](https://github.com/nirakov)  
* [Theo Paschôa](https://github.com/thpaschoa)  
* **Supervisor**: [Prof. José Maria Fernandes](https://www.ua.pt/pt/p/10319434)


## Technologies Used

- **Microcontrollers**: ESP32-DevKitC, ESP32-CAM  
- **Sensors**: MLX90640 (thermal camera), SEN0203 PPG sensor  
- **Mobile App**: Android (Kotlin, Jetpack Compose)  
- **Smartwatch**: Samsung Galaxy Watch 4 (WearOS)  
- **Communication**: BLE (Bluetooth Low Energy), MQTT (Mosquitto)  
- **Cloud**: Microsoft Azure (Dockerized backend)  
- **Backend Stack**: Node-RED, InfluxDB, Grafana  
- **Other Tools**: OpenCV, Docker, DataStore, RTC

## Features

### Android App
- User profile setup with HRmax estimation
- Real-time display of heart rate and temperature
- Heart rate zone tracking and feedback
- Support for both solo and group training modes
- MQTT publishing to backend (cloud/local)
- Offline mode with local storage
- BLE/WebSocket auto-reconnect

### Smartwatch App
- PPG heart rate acquisition (using Galaxy Watch 4 sensors)
- BLE broadcasting to Android app
- Lightweight UI with Jetpack Compose
- Low power consumption design

### Cloud Platform
- Docker on Azure VM
- Services: Mosquitto (MQTT), Node-RED (logic), InfluxDB (time-series DB), Grafana (dashboards)
- User and group dashboards
- Real-time monitoring for instructors


## Hardware Components (Consulted in June 2025)

To replicate this project, you will need the following hardware components:

- **ESP32-DevKitC**  
  A development board based on the ESP32 microcontroller used for reading sensor data and sending it via BLE or Wi-Fi.  
  [ESP32-S3-WROOM-1 Datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-s3-wroom-1_wroom-1u_datasheet_en.pdf)

- **SEN0203 PPG Sensor**  
  A photoplethysmography (PPG) sensor used for measuring heart rate by detecting blood volume changes.  
  [SEN0203 Datasheet](https://media.digikey.com/pdf/Data%20Sheets/DFRobot%20PDFs/SEN0203_Web.pdf)

- **ESP32-CAM**  
  An ESP32 board with a built-in camera module, optionally used for image capture or future enhancements.  
  [ESP32-CAM Datasheet](https://media.digikey.com/pdf/Data%20Sheets/DFRobot%20PDFs/DFR0602_Web.pdf)

- **MLX90640 Thermal Camera**  
  An infrared thermal imaging sensor for non-contact body temperature measurement.  
  [MLX90640 Datasheet](https://www.melexis.com/-/media/files/documents/datasheets/mlx90640-datasheet-melexis.pdf)

- **DS3231 RTC (Real-Time Clock)**  
  A high-precision clock module to timestamp sensor data accurately.  
  [DS3231 Datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/ds3231.pdf)

- **Samsung Galaxy Watch 4**  
  A WearOS smartwatch used to collect heart rate data through its built-in optical sensors. Communicates with the smartphone app via BLE.  
  [Product Page](https://www.samsung.com/pt/watches/galaxy-watch/galaxy-watch4-black-bluetooth-sm-r870nzkaphe/)


## Software & Tools Requirements

To set up and run the project, you will need:

- **Android Studio**  
  For building and deploying both the smartphone and smartwatch applications.

- **ESP-IDF or Arduino IDE**  
  For compiling and uploading the ESP32 firmware that interfaces with the sensors.

- **Azure account or local machine**  
  To host the backend infrastructure (Dockerized services).

- **Physical devices**  
  - ESP32-DevKitC  
  - SEN0203 PPG sensor  
  - MLX90640 thermal sensor  
  - ESP32-CAM (optional)  
  - DS3231 RTC  
  - Samsung Galaxy Watch 4 (WearOS)





