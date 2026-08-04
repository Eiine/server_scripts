#!/bin/bash

# Verificar que se ejecute como root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (sudo)."
  exit 1
fi

echo "=========================================="
echo "    CONFIGURADOR AUTOMÁTICO DE NETPLAN     "
echo "=========================================="

# 1. Obtener interfaces de red disponibles (PCI y USB)
echo "[*] Buscando interfaces de red disponibles..."
interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo"))

if [ ${#interfaces[@]} -eq 0 ]; then
  echo "[-] No se encontraron interfaces de red activas."
  exit 1
fi

echo ""
echo "Interfaces detectadas:"
for i in "${!interfaces[@]}"; do
  echo "  [$i] ${interfaces[$i]}"
done

# 2. Elegir interfaz
read -p "Selecciona el número de la interfaz que deseas configurar: " idx
selected_iface="${interfaces[$idx]}"

if [ -z "$selected_iface" ]; then
  echo "[-] Selección inválida."
  exit 1
fi

echo "[+] Has seleccionado: $selected_iface"

# 3. Detectar si la interfaz es inalámbrica (Wi-Fi) o cableada (Ethernet)
is_wifi=false
if iw dev 2>/dev/null | grep -q "$selected_iface"; then
  is_wifi=true
fi

netplan_config=""

if [ "$is_wifi" = true ]; then
  echo "[*] La interfaz $selected_iface es inalámbrica. Escaneando redes..."
  
  # Escanear redes Wi-Fi disponibles
  networks=$(iwlist "$selected_iface" scan 2>/dev/null | grep "ESSID" | sed 's/^[ \t]*//;s/ESSID://' | tr -d '"' | sort -u)
  
  if [ -z "$networks" ]; then
    echo "[-] No se pudieron detectar redes Wi-Fi. Asegúrate de que la tarjeta esté activa."
    exit 1
  fi

  echo ""
  echo "Redes Wi-Fi encontradas en rango:"
  select ssid in $networks; do
    if [ -n "$ssid" ]; then
      echo "[+] Has seleccionado la red: $ssid"
      break
    else
      echo "[-] Opción inválida."
    fi
  done

  read -s -p "Introduce la contraseña de la red Wi-Fi: " wifi_pass
  echo ""

  # Generar bloque Netplan para Wi-Fi (DHCP por defecto)
  netplan_config="network:
  version: 2
  renderer: networkd
  wifis:
    $selected_iface:
      dhcp4: true
      access-points:
        \"$ssid\":
          password: \"$wifi_pass\""

else
  echo "[*] La interfaz $selected_iface es cableada (Ethernet)."
  echo "[*] Configurando automáticamente con IP estática: 192.168.1.100"

  # Parámetros de red estática predeterminados (puedes cambiarlos si tu router usa otra puerta de enlace)
  gateway="192.168.1.1"
  dns_server="8.8.8.8"

  netplan_config="network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_iface:
      dhcp4: no
      addresses:
        - 192.168.1.100/24
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses:
          - $dns_server"
fi

# 4. Guardar el archivo en /etc/netplan/
netplan_file="/etc/netplan/01-netcfg.yaml"
echo "[*] Guardando configuración en $netplan_file..."

# Crear directorio si no existe
mkdir -p /etc/netplan

# Escribir la configuración
echo "$netplan_config" > "$netplan_file"

# Aplicar permisos seguros (necesario por las credenciales de Wi-Fi)
chmod 600 "$netplan_file"

echo "[+] Configuración guardada exitosamente."

# 5. Aplicar Netplan
echo "[*] Aplicando cambios con Netplan..."
netplan apply

if [ $? -eq 0 ]; then
  echo "[éxito] ¡Red configurada y aplicada correctamente!"
else
  echo "[-] Hubo un error al aplicar Netplan. Revisa la sintaxis del archivo."
fi
