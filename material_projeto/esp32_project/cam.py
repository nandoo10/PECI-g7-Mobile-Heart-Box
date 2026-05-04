import struct
import asyncio
import websockets
import paho.mqtt.client as mqtt
import numpy as np
import cv2
import base64

MQTT_BROKER = "172.20.10.6" # O teu IP confirmado
TOPIC_THERMAL = "heartbox/sensor/thermal"
TOPIC_IMAGE = "heartbox/cam/image"

# Inicialização do Cliente MQTT
try:
    mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    mqtt_client.connect(MQTT_BROKER, 1883)
    print(f" [OK] Conectado ao Broker LOCAL")
except Exception as e:
    print(f" [ERRO] Não foi possível ligar ao Mosquitto: {e}")

async def handle_connection(websocket, path=""):
    print("\n [SISTEMA] ESP32-CAM conectada via WebSocket!")
    try:
        async for message in websocket:
            if isinstance(message, bytes):
                # Recebendo os 768 píxeis térmicos (32x24)
                if len(message) == 3072:
                    todas_temps = struct.unpack('768f', message)
                    
                    # Filtra temperaturas válidas para a média do gráfico
                    v = [t for t in todas_temps if 10 < t < 80]
                    
                    if v:
                        # 1. CÁLCULO E ENVIO PARA O GRÁFICO (mantém-se igual)
                        t_min = round(min(v), 2)
                        t_max = round(max(v), 2)
                        t_avg = round(sum(v) / len(v), 2)
                        
                        print(f"-> Mín: {t_min}°C | Média: {t_avg}°C | Máx: {t_max}°C")
                        mqtt_client.publish(TOPIC_THERMAL, str(t_avg))
                        
                        # 2. GERAR A IMAGEM TÉRMICA "ULTRA SUAVE" (Igual à referência)
                        try:
                            matriz = np.array(todas_temps).reshape((24, 32))
                            
                            # Limpeza de ruído e píxeis mortos
                            matriz = np.where((matriz < 15) | (matriz > 60), t_avg, matriz)
                            
                            # Normalização
                            min_matriz, max_matriz = np.min(matriz), np.max(matriz)
                            if max_matriz > min_matriz:
                                norm = np.uint8((matriz - min_matriz) * 255 / (max_matriz - min_matriz))
                            else:
                                norm = np.zeros((24, 32), dtype=np.uint8)
                            
                            # Aplicar cores
                            img_colorida = cv2.applyColorMap(norm, cv2.COLORMAP_JET)
                            
                            # 1º Passo: Aumentar com interpolação Cúbica (ajuda a suavizar logo no redimensionamento)
                            img_ampliada = cv2.resize(img_colorida, (640, 480), interpolation=cv2.INTER_CUBIC)
                            
                            # 2º Passo: Aplicar um Blur Gaussiano forte (99, 99) para fundir as cores
                            # Nota: Os números têm de ser ímpares. Se (55,55) não chegar, usa (99,99)
                            img_suave = cv2.GaussianBlur(img_ampliada, (85, 85), 0)
                            
                            # Comprimir para garantir que não há lag no MQTT
                            encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 80]
                            _, buffer = cv2.imencode('.jpg', img_suave, encode_param)
                            img_base64 = base64.b64encode(buffer).decode('utf-8')
                            
                            mqtt_client.publish(TOPIC_IMAGE, img_base64)
                            
                        except Exception as erro_imagem:
                            print(f"Erro a processar imagem: {erro_imagem}")
            else:
                print(f"💬 Placa ESP32: {message}")

    except Exception as e:
        print(f"⚠️ Conexão encerrada ou erro: {e}")

async def main():
    print("-" * 40)
    print("   GATEWAY HEARTBOX ATIVO (LOCAL)   ")
    print("   A aguardar dados na porta 8080   ")
    print("-" * 40)
    
    async with websockets.serve(handle_connection, "0.0.0.0", 8080):
        await asyncio.Future()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n [SISTEMA] Gateway encerrado manualmente.")