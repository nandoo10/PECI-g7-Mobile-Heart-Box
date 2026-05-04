import struct
import asyncio
import websockets

async def handle_connection(websocket, path):
    print("ESP32-CAM conectada!")
    try:
        async for message in websocket:
            if isinstance(message, bytes) and len(message) == 3072:
                # Converte os 3072 bytes em 768 floats
                todas_temps = struct.unpack('768f', message)
                
                # FILTRO: Ignora píxeis mortos ou erros (valores > 100 ou < -10)
                temps_validas = [t for t in todas_temps if -10 < t < 100]
                
                if temps_validas:
                    t_max = max(temps_validas)
                    t_min = min(temps_validas)
                    t_avg = sum(temps_validas) / len(temps_validas)
                    
                    print(f"\n[DADOS TÉRMICOS FILTRADOS - {len(temps_validas)}/768 píxeis ok]")
                    print(f"Máxima: {t_max:.2f}°C | Mínima: {t_min:.2f}°C | Média: {t_avg:.2f}°C")
                    
                    if t_max > 30:
                        print("ESTADO: Detetada fonte de calor!")
                else:
                    print("Aviso: Todos os píxeis do frame são inválidos.")
            else:
                print(f"Mensagem: {message}")
    except Exception as e:
        print(f"Conexão encerrada: {e}")

async def main():
    # Cria o servidor WebSocket
    server = await websockets.serve(handle_connection, "0.0.0.0", 8080)
    print("Servidor WebSocket filtrado na porta 8080...")
    await server.wait_closed()  # Mantém o servidor a correr

# Executa o servidor usando asyncio.run() (Python 3.10+)
asyncio.run(main())