import asyncio
from bleak import BleakClient

# --- DADOS EXTRAÍDOS DO TEU NOVO .INO ---
ESP32_MAC_ADDRESS = "3C:8A:1F:D5:2E:AA" # Usa o endereço do scan.py
NAME_IN_CODE = "THERMAL_CAM-Heart_Box"

# UUIDs das características de escrita
UUID_SSID     = "ab35e54e-fde4-4f83-902a-07785de547b9"
UUID_PASS     = "c1c4b63b-bf3b-4e35-9077-d5426226c710"
UUID_SERVERIP = "0c954d7e-9249-456d-b949-cc079205d393"

# Teus dados reais
MEU_SSID = "iPhone de nando"
MINHA_PASS = "sportingcampeao2425"
MEU_IP_PC = "172.20.10.6:8080" # O código espera IP:PORTA

async def run():
    print(f"A conectar ao {NAME_IN_CODE} ({ESP32_MAC_ADDRESS})...")
    try:
        async with BleakClient(ESP32_MAC_ADDRESS) as client:
            print("✅ Ligado!")

            # 1. Enviar SSID
            print(f"A definir SSID: {MEU_SSID}")
            await client.write_gatt_char(UUID_SSID, MEU_SSID.encode())
            
            # 2. Enviar Password
            print(f"A definir Password: {MINHA_PASS}")
            await client.write_gatt_char(UUID_PASS, MINHA_PASS.encode())
            
            # 3. Enviar IP do Servidor
            print(f"A definir IP: {MEU_IP_PC}")
            await client.write_gatt_char(UUID_SERVERIP, MEU_IP_PC.encode())

            print("\n🚀 Tudo enviado! O ESP32 deve agora mudar para modo WIFI.")
            print("Verifica o Monitor Serial do Arduino.")

    except Exception as e:
        print(f"❌ Erro: {e}")

if __name__ == "__main__":
    asyncio.run(run())
    