# Projeto Final de Licenciatura — Mobile HeartBox

O projeto **Mobile HeartBox** propõe um sistema de telemetria desportiva e monitorização de saúde baseado numa arquitetura IoT. Ao contrário de ecossistemas comerciais fechados, esta solução permite a recolha, transmissão e armazenamento de dados biométricos (BPM, temperatura corporal) e dados de contexto (GPS, deteção de quedas, proximidade de obstáculos), garantindo ao utilizador o controlo total e acesso bruto ao seu histórico.

O sistema combina hardware com uma infraestrutura Cloud escalável, de forma a entregar monitorização em tempo real e análise histórica.

Este repositório está organizado em três componentes principais: firmware ESP32, aplicação móvel (Flutter) e backend (Node-RED).

> **Aviso importante:** O backend (Mosquitto, Node-RED, InfluxDB e Grafana) foi desenvolvido e testado num servidor Cloud na Azure, que tem um tempo limite de funcionamento e poderá já não estar ativo. Para testar o projeto, é necessário substituir o IP do servidor configurado nas ESPs (via BLE, na app, ou diretamente no código) pelo IP do computador onde o backend estiver a correr localmente.

---

# Códigos Finais — Mobile HeartBox

Esta pasta contém os três componentes principais de software/firmware desenvolvidos no âmbito do projeto.

## Estrutura

### `codigos_esp/`
Código-fonte dos microcontroladores ESP32 utilizados no sistema (ESP32-CAM, ESP32-S3-Zero).

### `thermal_app/`
Aplicação móvel desenvolvida em Flutter.

### `fluxo_NodeRed/`
Exportação do fluxo Node-RED utilizado no backend.

---

## Firmware ESP32 — `codigos_esp/`

Esta pasta contém o firmware das três placas utilizadas no sistema, desenvolvido em **Arduino IDE**. Cada placa deve ficar na sua própria subpasta, com o `.ino` correspondente:

```
codigos_esp/
├── esp32_cam/
│   └── esp32_cam.ino
├── esp32_s3/
│   └── esp32_s3.ino
└── esp32_s3_zero/
    └── esp32_s3_zero.ino
```

### Ambiente de desenvolvimento

- **Arduino IDE** (2.x)
- Boards Manager: instalar o package **"esp32 by Espressif Systems"**

### 1. `esp32_cam/` — Câmara térmica (ESP32-CAM)

Responsável pela leitura do sensor térmico MLX90640, RTC e envio de dados via MQTT/BLE.

**Board:** AI Thinker ESP32-CAM (ou equivalente com módulo de câmara)

**Bibliotecas necessárias (Library Manager):**
- `PubSubClient`
- `RTClib` (Adafruit)
- `Adafruit MLX90640`
- `Adafruit BusIO` (dependência do MLX90640)
- ESP32 core já inclui: `WiFi`, `Wire`, `Preferences`, `BLEDevice`/`BLEServer`/`BLEUtils`/`BLE2902`, `esp_camera`

**Notas de upload:**
- Pode ser necessário ligar o pino **GPIO0 ao GND** durante o upload (modo de flash) e desligar depois para correr o programa
- Verificar **Partition Scheme**: recomenda-se "Huge APP" devido ao uso da câmara

---

### 2. `esp32_s3/` — Sensores biométricos (ESP32-S3)

Responsável pela leitura de ECG (BPM), GPS, IMU (deteção de quedas) e comunicação MQTT/BLE.

**Board:** ESP32S3 Dev Module

**Bibliotecas necessárias (Library Manager):**
- `PubSubClient`
- `TinyGPSPlus`
- `Waveshare_10Dof-D` (biblioteca do IMU — verificar se foi instalada via .zip/manual)
- ESP32 core já inclui: `WiFi`, `Wire`, `Preferences`, `BLEDevice`/`BLEServer`/`BLEUtils`/`BLE2902`

**Configurações da board:**
- USB Mode: conforme variante da placa (USB-OTG ou Hardware CDC, dependendo do board específico)
- Verificar pinos definidos no código (`SDA_PIN`, `SCL_PIN`, `RXD2`, `TXD2`, `LO_PLUS`, `LO_MINUS`, `ECG_PIN`) correspondem à fiação real

---

### 3. `esp32_s3_zero/` — Sensor de proximidade (ESP32-S3-Zero)

Responsável pela leitura do sensor mmWave (proximidade de obstáculos) e envio de alertas via MQTT/BLE.

**Board:** ESP32S3 Dev Module (variante Zero)

**Bibliotecas necessárias (Library Manager):**
- `PubSubClient`
- ESP32 core já inclui: `WiFi`, `Preferences`, `BLEDevice`/`BLEServer`/`BLEUtils`/`BLE2902`, `HardwareSerial`

**Notas:**
- Sensor mmWave ligado via UART (`RX_PIN`/`TX_PIN` — verificar no código)
- Configuração inicial (Wi-Fi/MQTT) é feita via Bluetooth (BLE) na primeira utilização

---

### Configuração comum (todas as placas)

Todas as placas usam `Preferences` para guardar SSID, password e IP do servidor MQTT, configurados via BLE. Se não houver credenciais guardadas, a placa entra automaticamente em modo BLE para configuração.

---

## Fluxo Node-RED — `fluxo_NodeRed/`

Esta pasta contém a exportação do fluxo Node-RED utilizado no backend do sistema.

### Como importar

1. Abrir o Node-RED
2. Menu (☰) → **Import**
3. Colar/selecionar o ficheiro JSON do fluxo
4. **Import**

> Nota: requer o módulo `node-red-contrib-influxdb` instalado (Manage palette → Install).

---

## Aplicação Flutter — `thermal_app/`

Instruções de funcionamento da nossa app.

### Requisitos

Antes de executar o projeto é necessário ter instalado:

- Flutter SDK
- Android Studio
- Android SDK
- Dispositivo Android físico ou emulador

### Verificar instalação do Flutter

```bash
flutter doctor
```

### Preparação do dispositivo Android

Para executar a aplicação num dispositivo Android físico:

1. Ativar o **Modo Programador** no dispositivo Android
2. Ativar a opção **Depuração USB**
3. Ligar o dispositivo ao computador por USB

Para verificar se o dispositivo foi reconhecido pelo Flutter:

```bash
flutter devices
```

O dispositivo deverá aparecer na lista apresentada pelo comando.

### Instalação das dependências

Dentro da pasta `thermal_app`, executar:

```bash
flutter pub get
```

### Executar a aplicação

Com um dispositivo Android ligado ou emulador iniciado:

```bash
flutter run
```

### Estrutura principal do projeto

```
lib/main.dart    → código principal da aplicação
assets/          → recursos utilizados pela aplicação
android/         → configuração Android
ios/             → configuração iOS
```

### Dependências utilizadas

As dependências encontram-se no ficheiro `pubspec.yaml`.

---

> **Nota:** Projeto desenvolvido em Flutter para Android.

---

## Procedimento de utilização

Para um utilizador, o procedimento é o seguinte:

1. Ligar o telemóvel à rede Wi-Fi a usar (caso não sejam dados móveis)
2. Entrar na app
3. Fazer scan ao QR da caixa
4. Começar uma atividade e verificar se todos os dados estão a ser lidos
5. Caso estejam, realizar a atividade e, no fim, visualizar o histórico
6. Caso não estejam, dar scan novamente até que todas as ESPs estejam a funcionar corretamente

---

## Autores

- Martim Gomes, 119488
- Tiago Salgueiro, 119633
- Fernando Ferreira, 119758
- Gabriel Marta, 120155
- Jorge Marques, 120215