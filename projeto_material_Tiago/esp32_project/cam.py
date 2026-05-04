import struct
import asyncio
import websockets
import paho.mqtt.client as mqtt
import json
import os

MQTT_BROKER = "localhost" 
MQTT_TOPIC = "heartbox/sensor/thermal"

# Inicialização do Cliente MQTT
try:
    # Usamos a versão 1 da API para garantir compatibilidade com o teu ambiente
    mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
    mqtt_client.connect(MQTT_BROKER, 1883)
    print(f" [OK] Conectado ao Broker LOCAL (Docker)")
except Exception as e:
    print(f" [ERRO] Não foi possível ligar ao Mosquitto: {e}")

# Criar pasta para fotos se não existir
if not os.path.exists("fotos_recebidas"):
    os.makedirs("fotos_rece_bidas")

async def handle_connection(websocket, path):
    print("\n [SISTEMA] ESP32-CAM conectada via WebSocket!")
    try:
        async for message in websocket:
            if isinstance(message, bytes):
                # Se receber 3072 bytes, são dados térmicos (768 píxeis * 4 bytes)
                if len(message) == 3072:
                    todas_temps = struct.unpack('768f', message)
                    
                    # FILTRO: ignora píxeis mortos ou fora da gama térmica humana
                    v = [t for t in todas_temps if 10 < t < 80]
                    
                    if v:
                        # Média dos píxeis válidos
                        temperatura = round(sum(v) / len(v), 2)
                        
                        # PUBLICAÇÃO NO MQTT LOCAL
                        mqtt_client.publish(MQTT_TOPIC, str(temperatura))
                        print(f"-> Temperatura enviada para MQTT: {temperatura}°C")
                
                # Se for outro tamanho, assumimos que é a foto JPEG
                else:
                    with open("fotos_recebidas/ultima_foto.jpg", "wb") as f:
                        f.write(message)
                    print(f"-> Foto JPEG guardada ({len(message)} bytes)")
            
            else:
                # Mensagens de texto enviadas pela placa (logs)
                print(f"💬 Mensagem da placa: {message}")

    except Exception as e:
        print(f"⚠️ Conexão encerrada ou erro: {e}")

# Inicia o servidor na porta 8080
start_server = websockets.serve(handle_connection, "0.0.0.0", 8080)

print("-" * 40)
print("   GATEWAY HEARTBOX ATIVO (LOCAL)   ")
print("   A aguardar dados na porta 8080   ")
print("-" * 40)



asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()