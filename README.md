# Projeto Final de Licenciatura — Mobile HeartBox

O projeto **Mobile HeartBox** propõe um sistema de telemetria desportiva e monitorização de saúde baseado numa arquitetura IoT. Ao contrário de ecossistemas comerciais fechados, esta solução permite a recolha, transmissão e armazenamento de dados biométricos (BPM, temperatura corporal) e dados de contexto (GPS, deteção de quedas, proximidade de obstáculos), garantindo ao utilizador o controlo total e acesso bruto ao seu histórico.

O sistema combina hardware com uma infraestrutura Cloud escalável, de forma a entregar monitorização em tempo real e análise histórica.

Este repositório está organizado em três componentes principais: firmware ESP32, aplicação móvel (Flutter) e backend (Node-RED).

---

# Códigos Finais — Mobile HeartBox

Esta pasta contém os três componentes principais de software/firmware desenvolvidos no âmbito do projeto.

## Estrutura

### `codigos_esp/`
Código-fonte dos microcontroladores ESP32 utilizados no sistema (ESP32-CAM, ESP32-S3-Zero).

### `fluxo_NodeRed/`
Exportação do fluxo Node-RED utilizado no backend.

### `thermal_app/`
Aplicação móvel desenvolvida em Flutter.

---

## Acrescentem aqui a parte das esps !!!

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

## Autores

- Martim Gomes, 119488
- Tiago Salgueiro, 119633
- Fernando Ferreira, 119758
- Gabriel Marta, 120155
- Jorge Marques, 120215