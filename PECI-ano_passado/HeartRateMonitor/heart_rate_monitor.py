import paho.mqtt.client as mqtt

# Configurações MQTT
BROKER = "192.168.1.103"  # ip broker
PORT = 1883  # Porta padrão MQTT
TOPIC = "sw/bpm"  # tópico

# Callback para conexão
def on_connect(client, userdata, flags, rc):
    print(f"Conectado ao broker com código: {rc}")
    client.subscribe(TOPIC)  # Subscrição ao novo tópico

# Callback para mensagens
def on_message(client, userdata, msg):
    try:
        heart_rate = float(msg.payload.decode())  # Converte a mensagem recebida para float
        if heart_rate < 100:
            zone = "Aquecimento"
        elif 100 <= heart_rate < 140:
            zone = "Queima de gordura"
        elif 140 <= heart_rate < 170:
            zone = "Cardiovascular"
        else:
            zone = "Anaeróbico"

        print(f"Frequência cardíaca: {heart_rate} BPM, Zona: {zone}")
    except ValueError:
        print("Erro ao processar os dados recebidos.")

# Configuração do cliente MQTT
client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message

client.connect(BROKER, PORT, 60)

# Loop para manter a conexão e escutar as mensagens
client.loop_forever()
