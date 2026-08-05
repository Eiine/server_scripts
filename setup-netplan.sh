#!/bin/bash

# ============================================
# CONFIGURADOR AUTOMÁTICO DE NETPLAN
# IP FIJA: 192.168.1.100 (INTERFAZ SELECCIONADA)
# CON SISTEMA DE ROLLBACK INTEGRADO
# ============================================

# Colores para mejor legibilidad
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuración de red FIJA
STATIC_IP="192.168.1.100"
GATEWAY="192.168.1.1"
NETMASK="24"
DNS1="8.8.8.8"
DNS2="8.8.4.4"

# Variables globales
BACKUP_DIR=""
BACKUP_FILES=()
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"

# ============================================
# FUNCIONES AUXILIARES
# ============================================

print_error() { echo -e "${RED}[-] $1${NC}"; }
print_success() { echo -e "${GREEN}[+] $1${NC}"; }
print_info() { echo -e "${BLUE}[*] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }
print_title() { echo -e "${CYAN}=========================================="; echo -e "    $1"; echo -e "==========================================${NC}"; }

check_connectivity() {
    local timeout=3
    if ping -c 1 -W $timeout 8.8.8.8 &>/dev/null || ping -c 1 -W $timeout 1.1.1.1 &>/dev/null; then
        return 0
    else
        return 1
    fi
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        for octet in $(echo $ip | tr '.' ' '); do
            if [ $octet -lt 0 ] || [ $octet -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# ============================================
# FUNCIONES DE ROLLBACK
# ============================================

create_backup() {
    BACKUP_DIR="/tmp/netplan_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    print_info "Directorio de backup creado: $BACKUP_DIR"
    
    if [ -d "/etc/netplan" ]; then
        for config_file in /etc/netplan/*.yaml 2>/dev/null; do
            if [ -f "$config_file" ]; then
                cp "$config_file" "$BACKUP_DIR/"
                BACKUP_FILES+=("$config_file")
                print_info "Backup creado: $(basename "$config_file")"
            fi
        done
    fi
    
    ip addr show > "$BACKUP_DIR/ip_addr_backup.txt" 2>/dev/null
    ip route show > "$BACKUP_DIR/ip_route_backup.txt" 2>/dev/null
    
    print_success "Backup completado (${#BACKUP_FILES[@]} archivos)"
}

restore_backup() {
    print_title "RESTAURANDO CONFIGURACIÓN ANTERIOR"
    
    if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
        print_error "No se encontró directorio de backup válido."
        return 1
    fi
    
    local restored_count=0
    
    # Restaurar todos los archivos YAML respaldados originalmente con sus nombres exactos
    for backup_file in "$BACKUP_DIR"/*.yaml 2>/dev/null; do
        if [ -f "$backup_file" ]; then
            local filename=$(basename "$backup_file")
            local original_file="/etc/netplan/$filename"
            cp "$backup_file" "$original_file"
            print_success "Restaurado: $filename"
            ((restored_count++))
        fi
    done
    
    if [ $restored_count -eq 0 ]; then
        print_warning "No se encontraron archivos de backup previos. Limpiando y creando configuración DHCP por defecto..."
        
        local main_iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n1 | sed 's/@.*//')
        
        if [ -n "$main_iface" ]; then
            cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $main_iface:
      dhcp4: true
      optional: true
EOF
            print_success "Configuración DHCP creada para $main_iface en $NETPLAN_FILE"
        else
            print_error "No se pudo crear configuración por defecto"
            return 1
        fi
    fi
    
    print_info "Aplicando configuración restaurada..."
    if netplan apply 2>&1; then
        print_success "Configuración restaurada y aplicada"
        
        sleep 2
        if check_connectivity; then
            print_success "¡Conectividad restaurada exitosamente!"
        else
            print_warning "Configuración restaurada pero no hay conectividad a Internet"
        fi
        
        rm -rf "$BACKUP_DIR"
        print_info "Backups eliminados"
        return 0
    else
        print_error "Error al aplicar la configuración restaurada"
        return 1
    fi
}

show_backup_info() {
    if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
        print_error "No hay backups disponibles en la sesión actual"
        return 1
    fi
    
    print_info "Backup disponible en: $BACKUP_DIR"
    echo ""
    echo "Archivos respaldados:"
    ls -la "$BACKUP_DIR"/*.yaml 2>/dev/null || echo "  (ningún archivo .yaml)"
    echo ""
    echo "Para restaurar manualmente:"
    echo "  sudo cp $BACKUP_DIR/*.yaml /etc/netplan/ && sudo netplan apply"
    echo ""
}

# ============================================
# MENÚ PRINCIPAL
# ============================================

show_menu() {
    while true; do
        print_title "SISTEMA DE CONFIGURACIÓN DE RED"
        echo ""
        echo "1. Configurar interfaz de red (IP FIJA: $STATIC_IP)"
        echo "2. Restaurar configuración anterior (ROLLBACK)"
        echo "3. Ver información de backup"
        echo "4. Salir"
        echo ""
        read -p "Selecciona una opción [1-4]: " option
        
        case $option in
            1) configure_network ;;
            2) restore_backup ;;
            3) show_backup_info ;;
            4) echo "Saliendo..."; exit 0 ;;
            *) print_error "Opción inválida" ;;
        esac
        echo ""
        read -p "Presiona Enter para continuar..."
    done
}

# ============================================
# FUNCIÓN PRINCIPAL DE CONFIGURACIÓN
# ============================================

configure_network() {
    print_title "CONFIGURANDO INTERFAZ DE RED"
    echo "IP FIJA: $STATIC_IP"
    echo "Gateway: $GATEWAY"
    echo ""
    
    # Verificar root
    if [ "$EUID" -ne 0 ]; then
        print_error "Por favor, ejecuta este script como root (sudo)."
        return 1
    fi
    
    # Crear backup
    create_backup
    
    # Obtener interfaces
    print_info "Buscando interfaces de red disponibles..."
    mapfile -t interfaces < <(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | grep -v "@" | sed 's/@.*//')
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        print_error "No se encontraron interfaces de red activas."
        return 1
    fi
    
    echo ""
    echo "Interfaces detectadas:"
    for i in "${!interfaces[@]}"; do
        local is_wifi_check=false
        if [ -d "/sys/class/net/${interfaces[$i]}/wireless" ] || (command -v iw &>/dev/null && iw dev 2>/dev/null | grep -q "${interfaces[$i]}"); then
            is_wifi_check=true
        fi
        local type_info="Ethernet"
        [ "$is_wifi_check" = true ] && type_info="Wi-Fi"
        
        local ip_info=$(ip -4 addr show "${interfaces[$i]}" 2>/dev/null | grep inet | awk '{print $2}' | head -n1)
        local ip_display=""
        [ -n "$ip_info" ] && ip_display=" (IP: $ip_info)"
        
        echo "  [$i] ${interfaces[$i]} ($type_info)$ip_display"
    done
    
    # Seleccionar interfaz
    echo ""
    read -p "Selecciona el número de la interfaz que deseas configurar: " idx
    
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ -z "${interfaces[$idx]}" ]; then
        print_error "Selección inválida."
        return 1
    fi
    
    selected_iface="${interfaces[$idx]}"
    print_success "Has seleccionado: $selected_iface"
    
    # DETECCIÓN DE WI-FI (MEJORADA)
    local is_wifi=false
    if [ -d "/sys/class/net/$selected_iface/wireless" ]; then
        is_wifi=true
    elif command -v iw &>/dev/null; then
        if iw dev 2>/dev/null | grep -q "$selected_iface"; then
            is_wifi=true
        elif iw phy 2>/dev/null | grep -A20 "Wiphy" | grep -q "$selected_iface"; then
            is_wifi=true
        fi
    fi
    
    # Si es Wi-Fi, verificar drivers y nombre
    if [ "$is_wifi" = false ]; then
        local wifi_drivers="iwlwifi|ath|rtl|b43|brcm|wl|mt76|qca|ath9k"
        if lsmod 2>/dev/null | grep -qE "$wifi_drivers" && [[ "$selected_iface" =~ ^(wlan|wlp|wlx|ath|ra|wifi) ]]; then
            is_wifi=true
        fi
    fi
    
    # GENERAR CONFIGURACIÓN
    local netplan_config=""
    
    if [ "$is_wifi" = true ]; then
        print_info "Configurando interfaz Wi-Fi: $selected_iface con IP $STATIC_IP"
        ip link set "$selected_iface" up 2>/dev/null
        
        print_info "Escaneando redes Wi-Fi disponibles..."
        local networks=""
        if command -v iwlist &>/dev/null; then
            networks=$(iwlist "$selected_iface" scan 2>/dev/null | grep "ESSID" | sed 's/^[ \t]*//;s/ESSID://' | tr -d '"' | sort -u | grep -v "x00" | grep -v "^$")
        elif command -v nmcli &>/dev/null; then
            networks=$(nmcli -t -f SSID dev wifi list 2>/dev/null | sort -u)
        fi
        
        local ssid=""
        if [ -z "$networks" ]; then
            print_warning "No se detectaron redes automáticamente."
            read -p "Introduce el nombre de la red Wi-Fi (SSID) manualmente: " ssid
        else
            echo ""
            echo "Redes Wi-Fi encontradas:"
            select ssid in $networks; do
                if [ -n "$ssid" ]; then
                    print_success "Has seleccionado: $ssid"
                    break
                else
                    print_error "Opción inválida."
                fi
            done
        fi
        
        if [ -z "$ssid" ]; then
            print_error "No se proporcionó SSID."
            return 1
        fi
        
        read -s -p "Introduce la contraseña de la red Wi-Fi: " wifi_pass
        echo ""
        
        # Validar que la contraseña no esté vacía
        if [ -z "$wifi_pass" ]; then
            print_warning "Contraseña vacía. ¿Continuar? [s/N]: "
            read confirm
            if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
                return 1
            fi
        fi
        
        netplan_config="network:
  version: 2
  renderer: networkd
  wifis:
    $selected_iface:
      dhcp4: no
      addresses:
        - $STATIC_IP/$NETMASK
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$DNS1, $DNS2]
      access-points:
        \"$ssid\":
          password: \"$wifi_pass\""
    else
        print_info "Configurando interfaz Ethernet: $selected_iface con IP $STATIC_IP"
        
        netplan_config="network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_iface:
      dhcp4: no
      addresses:
        - $STATIC_IP/$NETMASK
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$DNS1, $DNS2]"
    fi
    
    # Guardar configuración
    print_info "Guardando configuración en $NETPLAN_FILE..."
    mkdir -p /etc/netplan
    
    # Backup del archivo actual si existe
    if [ -f "$NETPLAN_FILE" ]; then
        cp "$NETPLAN_FILE" "$BACKUP_DIR/"
        BACKUP_FILES+=("$NETPLAN_FILE")
    fi
    
    echo "$netplan_config" > "$NETPLAN_FILE"
    chmod 600 "$NETPLAN_FILE"
    print_success "Configuración guardada"
    
    # Verificar y aplicar
    print_info "Verificando sintaxis de Netplan..."
    if ! netplan generate 2>&1; then
        print_error "Error en la sintaxis de la configuración."
        print_info "Restaurando cambios..."
        restore_backup
        return 1
    fi
    
    print_info "Aplicando configuración..."
    if netplan apply 2>&1; then
        print_success "¡Red configurada exitosamente con IP $STATIC_IP!"
        
        sleep 2
        if check_connectivity; then
            print_success "¡Conectividad a Internet verificada!"
        else
            print_warning "Configuración aplicada pero no hay conectividad a Internet."
            print_info "Verifica que el gateway ($GATEWAY) sea correcto"
        fi
        
        echo ""
        print_info "IP asignada a $selected_iface:"
        ip -4 addr show "$selected_iface" | grep inet
        
        # Preguntar si eliminar backups
        if [ ${#BACKUP_FILES[@]} -gt 0 ]; then
            echo ""
            read -p "¿Deseas eliminar los backups? [s/N]: " delete_backups
            if [[ "$delete_backups" =~ ^[Ss]$ ]]; then
                rm -rf "$BACKUP_DIR"
                print_info "Backups eliminados"
            else
                print_info "Backups guardados en: $BACKUP_DIR"
                print_info "Puedes restaurar desde el menú principal (opción 2)"
            fi
        fi
        
        return 0
    else
        print_error "Error al aplicar Netplan"
        print_info "Restaurando cambios automáticamente..."
        restore_backup
        return 1
    fi
}

# ============================================
# INICIO DEL SCRIPT
# ============================================

if [ "$1" = "--rollback" ] || [ "$1" = "-r" ]; then
    BACKUP_DIR=$(ls -td /tmp/netplan_backup_* 2>/dev/null | head -n1)
    if [ -n "$BACKUP_DIR" ]; then
        restore_backup
        exit $?
    else
        print_error "No se encontraron backups para restaurar"
        exit 1
    fi
fi

show_menu