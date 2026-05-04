import paho.mqtt.client as mqtt
from influxdb import InfluxDBClient

# ===== CONFIGURAÇÃO =====
MQTT_BROKER = "172.20.10.8"
MQTT_PORT = 1883
MQTT_TOPIC = "sensor/ppg"
MQTT_USER = "esp32"     # username do broker
MQTT_PASS = "ppg123"    # password do broker

INFLUX_HOST = "localhost"
INFLUX_PORT = 8086
INFLUX_DB = "ppg_data"

# Conecta ao InfluxDB
influx_client = InfluxDBClient(host=INFLUX_HOST, port=INFLUX_PORT)
influx_client.create_database(INFLUX_DB)
influx_client.switch_database(INFLUX_DB)

# Callback quando chega uma mensagem MQTT
def on_message(client, userdata, msg):
    try:
        bpm = float(msg.payload.decode())
    except ValueError:
        print(f"Erro a processar payload: {msg.payload}")
        return

    json_body = [
        {
            "measurement": "ppg",
            "fields": {"bpm": bpm}
        }
    ]

    influx_client.write_points(json_body)
    print(f"[MQTT→InfluxDB] BPM: {bpm}")

# Configura MQTT
mqtt_client = mqtt.Client()
mqtt_client.username_pw_set(MQTT_USER, MQTT_PASS)  # <- adiciona aqui a autenticação
mqtt_client.on_message = on_message
mqtt_client.connect(MQTT_BROKER, MQTT_PORT)

mqtt_client.subscribe(MQTT_TOPIC)

print(f"Conectado ao broker {MQTT_BROKER}, escutando tópico '{MQTT_TOPIC}'...")
mqtt_client.loop_forever()
