#!/usr/bin/env bash
# ==============================================================================
# Script Name: gestor_servidor.sh
# Descripción: Respalda y restaura configuraciones críticas de un servidor 
#              (incluyendo Netplan, servicios de /etc, cron y paquetes).
# Compatible: Ubuntu Server / Debian (Bash)
# ==============================================================================

# Salir inmediatamente si ocurre un error crítico
set -Eeuo pipefail

DIRECTORIO_ACTUAL="$(pwd)"

echo "=========================================="
echo "    GESTOR DE CONFIGURACIONES DE SERVIDOR"
echo "=========================================="
echo "Selecciona una opción:"
echo "[1] Crear un respaldo de la configuración actual"
echo "[2] Restaurar un respaldo existente"
read -p "Opción (1 o 2): " opcion_principal
opcion_principal=$(echo "$opcion_principal" | xargs)

if [ "$opcion_principal" = "1" ]; then
    # ==========================================
    # SECCIÓN: CREAR RESPALDO (BACKUP)
    # ==========================================
    echo ""
    echo "--- INICIANDO PROCESO DE RESPALDO ---"
    
    read -p "Ingresa la ruta donde guardarás el respaldo [Por defecto: directorio actual]: " RUTA_INPUT
    RUTA_INPUT=$(echo "$RUTA_INPUT" | xargs)
    BACKUP_DEST="${RUTA_INPUT:-$DIRECTORIO_ACTUAL}"
    
    FECHA=$(date +"%Y%m%d_%H%M%S")
    BACKUP_PATH="$BACKUP_DEST/config_backup_$FECHA"
    
    echo "[*] Creando estructura temporal en: $BACKUP_PATH"
    mkdir -p "$BACKUP_PATH/etc/netplan"
    mkdir -p "$BACKUP_PATH/cron"
    
    # 1. Respaldar Netplan (red)
    echo "[*] Respaldando configuraciones de red (Netplan)..."
    if [ -d /etc/netplan ]; then
        cp -r /etc/netplan/*.yaml "$BACKUP_PATH/etc/netplan/" 2>/dev/null || echo "[!] No se encontraron archivos yaml de Netplan."
    fi
    
    # 2. Respaldar servicios y configuraciones de /etc
    echo "[*] Copiando configuraciones críticas de /etc..."
    cp -r /etc/ssh "$BACKUP_PATH/etc/" 2>/dev/null || true
    [ -f /etc/fstab ] && cp /etc/fstab "$BACKUP_PATH/etc/"
    [ -f /etc/crontab ] && cp /etc/crontab "$BACKUP_PATH/etc/"
    [ -d /etc/nginx ] && cp -r /etc/nginx "$BACKUP_PATH/etc/"
    [ -d /etc/samba ] && cp -r /etc/samba "$BACKUP_PATH/etc/"
    
    # 3. Respaldar crontabs de usuarios
    echo "[*] Respaldando crontabs..."
    cp -r /var/spool/cron/crontabs "$BACKUP_PATH/cron/" 2>/dev/null || true
    
    # 4. Guardar lista de paquetes instalados
    echo "[*] Guardando lista de paquetes instalados..."
    dpkg --get-selections > "$BACKUP_PATH/installed_packages.txt"
    
    # 5. Comprimir todo en un archivo .tar.gz limpio
    echo "[*] Comprimiendo el respaldo..."
    tar -czf "$BACKUP_DEST/backup_servidor_$FECHA.tar.gz" -C "$BACKUP_PATH" .
    rm -rf "$BACKUP_PATH"
    
    echo ""
    echo "[✔] ¡Respaldo completado con éxito!"
    echo "Archivo generado: $BACKUP_DEST/backup_servidor_$FECHA.tar.gz"

elif [ "$opcion_principal" = "2" ]; then
    # ==========================================
    # SECCIÓN: RESTAURAR RESPALDO
    # ==========================================
    if [ "$EUID" -ne 0 ]; then
      echo "[-] Error: Debes ejecutar la restauración como root (sudo)."
      exit 1
    fi
    
    echo ""
    echo "--- INICIANDO PROCESO DE RESTAURACIÓN ---"
    read -p "Ingresa la ruta completa del archivo comprimido (.tar.gz) del respaldo: " ARCHIVO_BACKUP
    ARCHIVO_BACKUP=$(echo "$ARCHIVO_BACKUP" | xargs)
    
    if [ ! -f "$ARCHIVO_BACKUP" ]; then
        echo "[-] Error: El archivo de respaldo especificado no existe."
        exit 1
    fi
    
    CARPETA_TEMP=$(mktemp -d)
    trap 'rm -rf "$CARPETA_TEMP"' EXIT
    
    echo "[*] Descomprimiendo el respaldo..."
    tar -xzf "$ARCHIVO_BACKUP" -C "$CARPETA_TEMP"
    
    # 1. Restaurar Netplan y aplicar red
    if [ -d "$CARPETA_TEMP/etc/netplan" ]; then
        echo "[*] Restaurando Netplan..."
        mkdir -p /etc/netplan
        cp -r "$CARPETA_TEMP/etc/netplan/"* /etc/netplan/ 2>/dev/null || true
        chmod 600 /etc/netplan/*.yaml 2>/dev/null || true
        
        echo "[*] Aplicando la configuración de red..."
        netplan apply || echo "[!] Advertencia: Revisa la configuración de Netplan; los nombres de interfaz física podrían haber cambiado."
    fi
    
    # 2. Restaurar archivos generales de /etc
    if [ -d "$CARPETA_TEMP/etc" ]; then
        echo "[*] Restaurando configuraciones de /etc..."
        [ -d "$CARPETA_TEMP/etc/ssh" ] && cp -r "$CARPETA_TEMP/etc/ssh" /etc/
        [ -f "$CARPETA_TEMP/etc/fstab" ] && cp "$CARPETA_TEMP/etc/fstab" /etc/
        [ -f "$CARPETA_TEMP/etc/crontab" ] && cp "$CARPETA_TEMP/etc/crontab" /etc/
        [ -d "$CARPETA_TEMP/etc/nginx" ] && cp -r "$CARPETA_TEMP/etc/nginx" /etc/
        [ -d "$CARPETA_TEMP/etc/samba" ] && cp -r "$CARPETA_TEMP/etc/samba" /etc/
    fi
    
    # 3. Restaurar crontabs
    if [ -d "$CARPETA_TEMP/cron/crontabs" ]; then
        echo "[*] Restaurando crontabs..."
        mkdir -p /var/spool/cron/
        cp -r "$CARPETA_TEMP/cron/crontabs" /var/spool/cron/
        chmod 600 /var/spool/cron/crontabs/* 2>/dev/null || true
    fi
    
    # 4. Restaurar paquetes instalados
    if [ -f "$CARPETA_TEMP/installed_packages.txt" ]; then
        read -p "¿Deseas restaurar e instalar los paquetes que tenías registrados? (s/n): " restaurar_pkgs
        restaurar_pkgs=$(echo "$restaurar_pkgs" | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ "$restaurar_pkgs" = "s" ] || [ "$restaurar_pkgs" = "si" ]; then
            echo "[*] Actualizando repositorios e instalando paquetes..."
            apt-get update
            dpkg --set-selections < "$CARPETA_TEMP/installed_packages.txt"
            apt-get dselect-upgrade -y
        fi
    fi
    
    echo ""
    echo "[✔] ¡Restauración completada con éxito! Se recomienda reiniciar el servidor."

else
    echo "Opción inválida. Ejecuta el script nuevamente y selecciona 1 o 2."
    exit 1
fi
