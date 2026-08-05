#!/bin/bash

# ============================================
# GESTOR DE VENTILADORES MACBOOK (MACFANCTLD)
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_error() { echo -e "${RED}[-] $1${NC}"; }
print_success() { echo -e "${GREEN}[+] $1${NC}"; }
print_info() { echo -e "${BLUE}[*] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }
print_title() { echo -e "${CYAN}=========================================="; echo -e "    $1"; echo -e "==========================================${NC}"; }

# Verificar privilegios de root
if [ "$EUID" -ne 0 ]; then
    print_error "Por favor, ejecuta este script como root (sudo)."
    exit 1
fi

CONFIG_FILE="/etc/macfanctld.conf"

show_status() {
    print_title "ESTADO ACTUAL DE LA MACBOOK"
    
    echo ""
    echo "--- Temperaturas del Sistema ---"
    if command -v sensors &>/dev/null; then
        sensors 2>/dev/null
    else
        print_warning "Instala 'lm-sensors' para ver el detalle completo de temperaturas."
    fi
    
    echo ""
    echo "--- Estado del Demonio macfanctld ---"
    systemctl status macfanctld --no-pager | grep -E "Active:|Loaded:"
    
    echo ""
    echo "--- Configuración actual en $CONFIG_FILE ---"
    if [ -f "$CONFIG_FILE" ]; then
        grep -v "^#" "$CONFIG_FILE" | grep -v "^$"
    else
        print_error "No se encontró el archivo de configuración $CONFIG_FILE"
    fi
    echo ""
}

configure_thresholds() {
    print_title "MODIFICAR UMBRALES DE MACFANCTLD"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "El archivo de configuración no existe."
        return
    fi

    print_info "Valores actuales en el archivo de configuración:"
    grep -E "fan_min|fan_max|temp_min|temp_max|temp_high" "$CONFIG_FILE" 2>/dev/null
    
    echo ""
    read -p "Introduce la temperatura mínima (temp_min, ej. 55): " t_min
    read -p "Introduce la temperatura alta (temp_high, ej. 65): " t_high
    read -p "Introduce la temperatura máxima (temp_max, ej. 85): " t_max
    
    if ! [[ "$t_min" =~ ^[0-9]+$ ]] || ! [[ "$t_high" =~ ^[0-9]+$ ]] || ! [[ "$t_max" =~ ^[0-9]+$ ]]; then
        print_error "Por favor, introduce únicamente valores numéricos."
        return
    fi
    
    # Actualizar o insertar valores en macfanctld.conf
    sed -i "s/^temp_min.*/temp_min: $t_min/" "$CONFIG_FILE"
    sed -i "s/^temp_high.*/temp_high: $t_high/" "$CONFIG_FILE"
    sed -i "s/^temp_max.*/temp_max: $t_max/" "$CONFIG_FILE"
    
    print_info "Reiniciando el servicio macfanctld para aplicar cambios..."
    systemctl restart macfanctld
    
    if [ $? -eq 0 ]; then
        print_success "¡Umbrales actualizados y servicio reiniciado con éxito!"
    else
        print_error "Hubo un error al reiniciar el servicio."
    fi
}

apply_profile() {
    local p_min=$1
    local p_high=$2
    local p_max=$3
    local profile_name=$4

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "El archivo de configuración no existe."
        return
    fi

    print_info "Aplicando perfil: $profile_name..."

    # Ajustar velocidad mínima a 3000 RPM en base y configurar los umbrales
    sed -i "s/^fan_min.*/fan_min: 3000/" "$CONFIG_FILE"
    sed -i "s/^temp_min.*/temp_min: $p_min/" "$CONFIG_FILE"
    sed -i "s/^temp_high.*/temp_high: $p_high/" "$CONFIG_FILE"
    sed -i "s/^temp_max.*/temp_max: $p_max/" "$CONFIG_FILE"

    print_info "Reiniciando el servicio macfanctld..."
    systemctl restart macfanctld

    if [ $? -eq 0 ]; then
        print_success "¡Perfil '$profile_name' aplicado correctamente (fan_min: 3000 RPM, inicio: $p_min°C, max: $p_max°C)!"
    else
        print_error "Hubo un error al reiniciar el servicio."
    fi
}

show_profiles_menu() {
    while true; do
        print_title "SELECCIÓN DE PERFILES ESTACIONALES"
        echo "1. Verano   (Inicio: 60°C | Máximo: 70°C | Base: 3000 RPM)"
        echo "2. Templado (Inicio: 65°C | Máximo: 75°C | Base: 3000 RPM)"
        echo "3. Invierno (Inicio: 70°C | Máximo: 85°C | Base: 3000 RPM)"
        echo "4. Volver al menú principal"
        echo ""
        read -p "Selecciona un perfil [1-4]: " p_option

        case $p_option in
            1) apply_profile 60 65 70 "Verano"; break ;;
            2) apply_profile 65 70 75 "Templado"; break ;;
            3) apply_profile 70 77 85 "Invierno"; break ;;
            4) break ;;
            *) print_error "Opción inválida" ;;
        esac
        echo ""
        read -p "Presiona Enter para continuar..."
    done
}

# Menú principal interactivo
while true; do
    print_title "CONTROLADOR DE COOLERS (MACBOOK + MACFANCTLD)"
    echo "1. Ver estado actual (Sensores y Configuración)"
    echo "2. Cambiar umbrales de temperatura (Personalizado)"
    echo "3. Perfiles preconfigurados (Verano / Templado / Invierno)"
    echo "4. Salir"
    echo ""
    read -p "Selecciona una opción [1-4]: " option
    
    case $option in
        1) show_status ;;
        2) configure_thresholds ;;
        3) show_profiles_menu ;;
        4) echo "Saliendo..."; exit 0 ;;
        *) print_error "Opción inválida" ;;
    esac
    
    echo ""
    read -p "Presiona Enter para continuar..."
done