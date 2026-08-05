#!/bin/bash

# ============================================
# GESTOR DE VENTILADORES MACBOOK (MACFANCTLD)
# VERSIÓN MEJORADA - ESTABLE
# ============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Funciones de impresión
print_error() { echo -e "${RED}[-] $1${NC}"; }
print_success() { echo -e "${GREEN}[+] $1${NC}"; }
print_info() { echo -e "${BLUE}[*] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }
print_title() { 
    echo -e "${CYAN}=========================================="
    echo -e "    $1"
    echo -e "==========================================${NC}"
}
print_subtitle() {
    echo -e "${MAGENTA}--- $1 ---${NC}"
}

# Variables globales
CONFIG_FILE="/etc/macfanctld.conf"
BACKUP_DIR="/etc/macfanctld.backups"

# ============================================
# FUNCIONES DE VERIFICACIÓN Y UTILIDADES
# ============================================

check_dependencies() {
    local missing_deps=0
    
    print_info "Verificando dependencias..."
    
    # Verificar macfanctld
    if ! command -v macfanctld &>/dev/null; then
        print_error "macfanctld no está instalado."
        print_info "Opciones de instalación:"
        echo "  - Debian/Ubuntu: sudo apt install macfanctld"
        echo "  - Arch Linux: sudo pacman -S macfanctld"
        echo "  - Fedora: sudo dnf install macfanctld"
        echo "  - Desde fuente: https://github.com/Monkkee/macfanctld"
        missing_deps=1
    fi
    
    # Verificar servicio systemd
    if ! systemctl list-unit-files 2>/dev/null | grep -q macfanctld; then
        print_error "El servicio macfanctld no está configurado."
        missing_deps=1
    fi
    
    if [ $missing_deps -eq 1 ]; then
        exit 1
    fi
    
    # Verificar si está activo
    if ! systemctl is-active --quiet macfanctld; then
        print_warning "macfanctld no está activo. Iniciando servicio..."
        systemctl start macfanctld
        if [ $? -eq 0 ]; then
            print_success "Servicio iniciado correctamente."
        else
            print_error "No se pudo iniciar macfanctld."
            exit 1
        fi
    fi
    
    print_success "Todas las dependencias están satisfechas."
}

create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        print_info "Directorio de backups creado: $BACKUP_DIR"
    fi
}

backup_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "No hay archivo de configuración para respaldar."
        return 1
    fi
    
    create_backup_dir
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/macfanctld.conf.bak.$timestamp"
    
    cp "$CONFIG_FILE" "$backup_file"
    if [ $? -eq 0 ]; then
        print_success "Backup creado: $backup_file"
        return 0
    else
        print_error "Error al crear backup."
        return 1
    fi
}

restore_backup() {
    print_title "RESTAURAR BACKUP"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "No hay directorio de backups."
        return 1
    fi
    
    local backups=($(ls -1t "$BACKUP_DIR"/macfanctld.conf.bak.* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_error "No se encontraron backups."
        return 1
    fi
    
    echo "Backups disponibles:"
    for i in "${!backups[@]}"; do
        echo "  $((i+1)). $(basename "${backups[$i]}")"
    done
    echo "  0. Cancelar"
    echo ""
    read -p "Selecciona un backup [0-${#backups[@]}]: " choice
    
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        print_info "Operación cancelada."
        return 0
    fi
    
    if [ "$choice" -gt 0 ] && [ "$choice" -le ${#backups[@]} ] 2>/dev/null; then
        local selected="${backups[$((choice-1))]}"
        cp "$selected" "$CONFIG_FILE"
        if [ $? -eq 0 ]; then
            print_success "Backup restaurado correctamente."
            systemctl restart macfanctld
            if [ $? -eq 0 ]; then
                print_success "Servicio reiniciado con éxito."
            fi
        else
            print_error "Error al restaurar backup."
        fi
    else
        print_error "Opción inválida."
    fi
}

set_config_value() {
    local key=$1
    local value=$2
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "El archivo de configuración no existe."
        return 1
    fi
    
    if grep -q "^$key:" "$CONFIG_FILE"; then
        sed -i "s/^$key:.*/$key: $value/" "$CONFIG_FILE"
    else
        echo "$key: $value" >> "$CONFIG_FILE"
    fi
    
    return 0
}

get_config_value() {
    local key=$1
    if [ -f "$CONFIG_FILE" ]; then
        grep "^$key:" "$CONFIG_FILE" | cut -d':' -f2 | tr -d ' '
    fi
}

validate_temperature() {
    local temp=$1
    if ! [[ "$temp" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if [ "$temp" -lt 0 ] || [ "$temp" -gt 100 ]; then
        return 1
    fi
    return 0
}

# ============================================
# FUNCIONES PRINCIPALES DEL GESTOR
# ============================================

show_status() {
    print_title "ESTADO ACTUAL DE LA MACBOOK"
    
    # Temperaturas
    echo ""
    print_subtitle "TEMPERATURAS DEL SISTEMA"
    if command -v sensors &>/dev/null; then
        sensors 2>/dev/null | grep -E "Core|Package|temp|Tdie|Tctl" || sensors 2>/dev/null
    else
        print_warning "'lm-sensors' no está instalado."
        print_info "Instala con: sudo apt install lm-sensors  (Debian/Ubuntu)"
        print_info "O: sudo dnf install lm_sensors  (Fedora/RHEL)"
        print_info "Luego ejecuta: sudo sensors-detect"
    fi
    
    # RPM de ventiladores
    echo ""
    print_subtitle "RPM DE VENTILADORES"
    if [ -d "/sys/devices/platform/applesmc.768" ]; then
        for i in {0..2}; do
            if [ -f "/sys/devices/platform/applesmc.768/fan${i}_input" ]; then
                rpm=$(cat "/sys/devices/platform/applesmc.768/fan${i}_input" 2>/dev/null)
                if [ -n "$rpm" ]; then
                    local label=$(cat "/sys/devices/platform/applesmc.768/fan${i}_label" 2>/dev/null || echo "Ventilador $((i+1))")
                    echo "  $label: $rpm RPM"
                fi
            fi
        done
    else
        print_warning "No se encontraron ventiladores Apple SMC."
        # Intento alternativo con pmset para MacBook
        if command -v pmset &>/dev/null; then
            pmset -g therm 2>/dev/null | grep -E "Fan|RPM"
        fi
    fi
    
    # Estado del servicio
    echo ""
    print_subtitle "ESTADO DEL SERVICIO"
    systemctl status macfanctld --no-pager | grep -E "Active:|Loaded:|Main PID:|Since:"
    
    # Configuración actual
    echo ""
    print_subtitle "CONFIGURACIÓN ACTUAL"
    if [ -f "$CONFIG_FILE" ]; then
        echo "  Archivo: $CONFIG_FILE"
        echo ""
        local config_content=$(grep -v "^#" "$CONFIG_FILE" | grep -v "^$" | sed 's/^/  /')
        if [ -n "$config_content" ]; then
            echo "$config_content"
        else
            echo "  (Sin configuración personalizada - usando valores por defecto)"
        fi
    else
        print_warning "No se encontró archivo de configuración: $CONFIG_FILE"
        echo "  Usando valores por defecto de macfanctld"
    fi
    
    echo ""
}

configure_thresholds() {
    print_title "CONFIGURACIÓN MANUAL DE UMBRALES"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "El archivo de configuración no existe."
        print_info "Creando archivo de configuración por defecto..."
        touch "$CONFIG_FILE"
        echo "fan_min: 3000" >> "$CONFIG_FILE"
        echo "fan_max: 6200" >> "$CONFIG_FILE"
        echo "temp_min: 55" >> "$CONFIG_FILE"
        echo "temp_high: 65" >> "$CONFIG_FILE" 
        echo "temp_max: 85" >> "$CONFIG_FILE"
        print_success "Archivo creado con valores por defecto."
    fi

    # Mostrar valores actuales
    print_info "Valores actuales:"
    echo ""
    local current_min=$(get_config_value "fan_min")
    local current_max=$(get_config_value "fan_max")
    local current_temp_min=$(get_config_value "temp_min")
    local current_temp_high=$(get_config_value "temp_high")
    local current_temp_max=$(get_config_value "temp_max")
    
    echo "  Velocidad mínima: ${current_min:-3000} RPM"
    echo "  Velocidad máxima: ${current_max:-6200} RPM"
    echo "  Temp mínima: ${current_temp_min:-55}°C"
    echo "  Temp alta: ${current_temp_high:-65}°C"
    echo "  Temp máxima: ${current_temp_max:-85}°C"
    echo ""
    
    # Hacer backup antes de modificar
    print_info "Creando backup de la configuración actual..."
    backup_config
    
    # Solicitar nuevos valores
    echo "Introduce nuevos valores (presiona Enter para mantener el actual):"
    echo ""
    
    read -p "Velocidad mínima (RPM) [${current_min:-3000}]: " fan_min
    fan_min=${fan_min:-$current_min}
    
    read -p "Velocidad máxima (RPM) [${current_max:-6200}]: " fan_max
    fan_max=${fan_max:-$current_max}
    
    read -p "Temp mínima (°C) [${current_temp_min:-55}]: " t_min
    t_min=${t_min:-$current_temp_min}
    
    read -p "Temp alta (°C) [${current_temp_high:-65}]: " t_high
    t_high=${t_high:-$current_temp_high}
    
    read -p "Temp máxima (°C) [${current_temp_max:-85}]: " t_max
    t_max=${t_max:-$current_temp_max}
    
    # Validaciones
    local has_error=0
    
    if ! validate_temperature "$t_min" || ! validate_temperature "$t_high" || ! validate_temperature "$t_max"; then
        print_error "Las temperaturas deben ser números entre 0 y 100."
        has_error=1
    fi
    
    if ! [[ "$fan_min" =~ ^[0-9]+$ ]] || ! [[ "$fan_max" =~ ^[0-9]+$ ]]; then
        print_error "Las RPM deben ser números."
        has_error=1
    fi
    
    if [ $has_error -eq 0 ]; then
        if [ $t_min -ge $t_high ] || [ $t_high -ge $t_max ]; then
            print_error "Las temperaturas deben cumplir: temp_min < temp_high < temp_max"
            has_error=1
        fi
        
        if [ $fan_min -ge $fan_max ]; then
            print_error "La velocidad mínima debe ser menor que la máxima."
            has_error=1
        fi
    fi
    
    if [ $has_error -eq 1 ]; then
        print_error "No se aplicaron los cambios. Corrige los valores y vuelve a intentarlo."
        return 1
    fi
    
    # Aplicar valores
    set_config_value "fan_min" "$fan_min"
    set_config_value "fan_max" "$fan_max"
    set_config_value "temp_min" "$t_min"
    set_config_value "temp_high" "$t_high"
    set_config_value "temp_max" "$t_max"
    
    print_info "Reiniciando el servicio para aplicar cambios..."
    systemctl restart macfanctld
    
    if [ $? -eq 0 ]; then
        print_success "¡Configuración actualizada y servicio reiniciado con éxito!"
        print_info "Nuevos valores:"
        echo "  Velocidad mínima: $fan_min RPM"
        echo "  Velocidad máxima: $fan_max RPM"
        echo "  Temp mínima: $t_min°C"
        echo "  Temp alta: $t_high°C"
        echo "  Temp máxima: $t_max°C"
    else
        print_error "Hubo un error al reiniciar el servicio."
        print_info "Intentando restaurar backup..."
        # Aquí se podría implementar una restauración automática
    fi
}

apply_profile() {
    local profile_name=$1
    local fan_min=$2
    local fan_max=$3
    local temp_min=$4
    local temp_high=$5
    local temp_max=$6

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "El archivo de configuración no existe."
        print_info "Creando archivo de configuración..."
        touch "$CONFIG_FILE"
        echo "fan_min: 3000" >> "$CONFIG_FILE"
        echo "fan_max: 6200" >> "$CONFIG_FILE"
        echo "temp_min: 55" >> "$CONFIG_FILE"
        echo "temp_high: 65" >> "$CONFIG_FILE"
        echo "temp_max: 85" >> "$CONFIG_FILE"
    fi

    print_info "Aplicando perfil: $profile_name..."
    backup_config

    set_config_value "fan_min" "$fan_min"
    set_config_value "fan_max" "$fan_max"
    set_config_value "temp_min" "$temp_min"
    set_config_value "temp_high" "$temp_high"
    set_config_value "temp_max" "$temp_max"

    print_info "Reiniciando el servicio..."
    systemctl restart macfanctld

    if [ $? -eq 0 ]; then
        print_success "✓ Perfil '$profile_name' aplicado correctamente."
        echo "  Configuración:"
        echo "  - Velocidad mínima: $fan_min RPM"
        echo "  - Velocidad máxima: $fan_max RPM"
        echo "  - Temperatura mínima: $temp_min°C"
        echo "  - Temperatura alta: $temp_high°C"
        echo "  - Temperatura máxima: $temp_max°C"
    else
        print_error "Error al aplicar el perfil. Intentando restaurar..."
        # Intentar restaurar del último backup
        local last_backup=$(ls -1t "$BACKUP_DIR"/macfanctld.conf.bak.* 2>/dev/null | head -1)
        if [ -n "$last_backup" ]; then
            cp "$last_backup" "$CONFIG_FILE"
            systemctl restart macfanctld
            print_info "Configuración restaurada desde backup."
        fi
    fi
}

show_profiles_menu() {
    while true; do
        print_title "SELECCIÓN DE PERFILES ESTACIONALES"
        echo ""
        echo "  ESTRATEGIAS DE REFRIGERACIÓN:"
        echo "  ┌─────────────────────────────────────────────────────────┐"
        echo "  │ 1. 🔥 Verano    (Más agresivo - prioriza enfriamiento) │"
        echo "  │ 2. 🌤️  Templado (Balanceado - uso diario)              │"
        echo "  │ 3. ❄️  Invierno (Moderado - prioriza silencio)         │"
        echo "  │ 4. 🎮 Rendimiento (Máximo enfriamiento para gaming)   │"
        echo "  │ 5. 🔇 Silencioso (Mínimo ruido para trabajo ligero)   │"
        echo "  │ 6. 📊 Mostrar comparativa de perfiles                 │"
        echo "  │ 7. ↩️  Volver al menú principal                        │"
        echo "  └─────────────────────────────────────────────────────────┘"
        echo ""
        read -p "Selecciona una opción [1-7]: " p_option
        echo ""

        case $p_option in
            1) apply_profile "Verano" 3000 6200 55 60 70; break ;;
            2) apply_profile "Templado" 3000 6000 60 67 78; break ;;
            3) apply_profile "Invierno" 3000 5500 65 72 85; break ;;
            4) apply_profile "Rendimiento" 3500 6500 50 55 65; break ;;
            5) apply_profile "Silencioso" 2000 4500 70 78 85; break ;;
            6) show_profiles_comparison ;;
            7) break ;;
            *) print_error "Opción inválida" ;;
        esac
        echo ""
        read -p "Presiona Enter para continuar..."
    done
}

show_profiles_comparison() {
    print_title "COMPARATIVA DE PERFILES"
    echo ""
    printf "%-15s | %-10s | %-10s | %-10s | %-10s | %-10s\n" "PERFIL" "FAN MIN" "FAN MAX" "TEMP MIN" "TEMP HIGH" "TEMP MAX"
    printf "%s\n" "─────────────────────────────────────────────────────────────────────────────"
    printf "%-15s | %-10s | %-10s | %-10s | %-10s | %-10s\n" "Verano" "3000" "6200" "55" "60" "70"
    printf "%-15s | %-10s | %-10s | %-10s | %-10s | %-10s\n" "Templado" "3000" "6000" "60" "67" "78"
    printf "%-15s | %-10s | %-10s | %-10s | %-10s | %-10s\n" "Invierno" "3000" "5500" "65" "72" "85"
    printf "%-15s | %-10s | %-10s | %-10s | %-10s | %-10s\n" "Rendimiento" "3500" "6500" "50" "55" "65"
    printf "%-15s | %-10s | %-10s | %-10s | %-10s | %-10s\n" "Silencioso" "2000" "4500" "70" "78" "85"
    echo ""
    print_info "NOTA: La velocidad mínima (FAN MIN) es la base, la máxima (FAN MAX) es el tope."
    print_info "Temperaturas en grados Celsius (°C)"
    echo ""
    read -p "Presiona Enter para continuar..."
}

manage_service() {
    print_title "GESTIÓN DEL SERVICIO MACFANCTLD"
    echo ""
    echo "  1. Iniciar servicio"
    echo "  2. Detener servicio"
    echo "  3. Reiniciar servicio"
    echo "  4. Ver logs del servicio"
    echo "  5. Habilitar inicio automático"
    echo "  6. Deshabilitar inicio automático"
    echo "  7. Volver al menú principal"
    echo ""
    read -p "Selecciona una opción [1-7]: " s_option
    
    case $s_option in
        1)
            systemctl start macfanctld
            if [ $? -eq 0 ]; then
                print_success "Servicio iniciado correctamente."
            else
                print_error "Error al iniciar el servicio."
            fi
            ;;
        2)
            systemctl stop macfanctld
            if [ $? -eq 0 ]; then
                print_warning "Servicio detenido. ¡Cuidado! Los ventiladores usarán configuración por defecto."
            else
                print_error "Error al detener el servicio."
            fi
            ;;
        3)
            systemctl restart macfanctld
            if [ $? -eq 0 ]; then
                print_success "Servicio reiniciado correctamente."
            else
                print_error "Error al reiniciar el servicio."
            fi
            ;;
        4)
            print_title "ÚLTIMOS LOGS DE MACFANCTLD"
            journalctl -u macfanctld -n 30 --no-pager
            echo ""
            read -p "Presiona Enter para continuar..."
            ;;
        5)
            systemctl enable macfanctld
            if [ $? -eq 0 ]; then
                print_success "Inicio automático habilitado."
            else
                print_error "Error al habilitar inicio automático."
            fi
            ;;
        6)
            systemctl disable macfanctld
            if [ $? -eq 0 ]; then
                print_warning "Inicio automático deshabilitado."
            else
                print_error "Error al deshabilitar inicio automático."
            fi
            ;;
        7) return ;;
        *) print_error "Opción inválida" ;;
    esac
    echo ""
    read -p "Presiona Enter para continuar..."
}

# ============================================
# MENÚ PRINCIPAL
# ============================================

show_main_menu() {
    while true; do
        print_title "CONTROLADOR DE COOLERS MACBOOK"
        echo ""
        echo "  ┌─────────────────────────────────────────────────────────┐"
        echo "  │ 1. 📊 Ver estado actual                               │"
        echo "  │ 2. ⚙️  Configuración personalizada                    │"
        echo "  │ 3. 🎯 Perfiles preconfigurados                       │"
        echo "  │ 4. 🔄 Restaurar backup                              │"
        echo "  │ 5. 🛠️  Gestión del servicio                         │"
        echo "  │ 6. ℹ️  Información del sistema                       │"
        echo "  │ 7. 🚪 Salir                                         │"
        echo "  └─────────────────────────────────────────────────────────┘"
        echo ""
        read -p "Selecciona una opción [1-7]: " option
        echo ""

        case $option in
            1) show_status ;;
            2) configure_thresholds ;;
            3) show_profiles_menu ;;
            4) restore_backup ;;
            5) manage_service ;;
            6) show_system_info ;;
            7) 
                print_success "¡Hasta luego! Mantén tu MacBook fresco. ❄️"
                exit 0 
                ;;
            *) print_error "Opción inválida. Por favor, selecciona 1-7." ;;
        esac
        
        if [ "$option" != "7" ] && [ "$option" != "6" ] && [ "$option" != "4" ]; then
            echo ""
            read -p "Presiona Enter para continuar..."
        fi
    done
}

# ============================================
# SISTEMA DE INFORMACIÓN ADICIONAL
# ============================================

show_system_info() {
    print_title "INFORMACIÓN DEL SISTEMA"
    
    echo ""
    print_subtitle "HARDWARE"
    echo "  Modelo: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Desconocido")"
    echo "  CPU: $(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d':' -f2 | xargs)"
    echo "  Núcleos: $(nproc)"
    echo "  RAM: $(free -h | grep Mem | awk '{print $2}')"
    
    echo ""
    print_subtitle "SISTEMA OPERATIVO"
    echo "  OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Desconocido")"
    echo "  Kernel: $(uname -r)"
    echo "  Arquitectura: $(uname -m)"
    
    echo ""
    print_subtitle "MACFANCTLD"
    echo "  Versión: $(macfanctld -V 2>/dev/null || echo "Desconocida")"
    echo "  Estado: $(systemctl is-active macfanctld 2>/dev/null || echo "Inactivo")"
    
    echo ""
    print_subtitle "TEMPERATURA AMBIENTE ESTIMADA"
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        local ambient=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}')
        if [ -n "$ambient" ]; then
            echo "  ~$ambient°C (aproximada)"
        fi
    fi
    
    echo ""
    print_warning "Para información más detallada de hardware, ejecuta: sudo dmidecode"
    echo ""
}

# ============================================
# INICIO DEL SCRIPT
# ============================================

# Verificar privilegios de root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root (sudo)."
    print_info "Ejecuta: sudo $0"
    exit 1
fi

# Banner de inicio
clear
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║                                                           ║"
echo "  ║   🍏  GESTOR DE VENTILADORES MACBOOK  🍏                ║"
echo "  ║                                                           ║"
echo "  ║   Control inteligente de refrigeración para tu MacBook   ║"
echo "  ║                                                           ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Verificar dependencias
check_dependencies

# Crear directorio de backups
create_backup_dir

# Crear archivo de configuración si no existe
if [ ! -f "$CONFIG_FILE" ]; then
    print_warning "No se encontró archivo de configuración. Creando uno por defecto..."
    touch "$CONFIG_FILE"
    echo "# Configuración por defecto para macfanctld" > "$CONFIG_FILE"
    echo "fan_min: 3000" >> "$CONFIG_FILE"
    echo "fan_max: 6200" >> "$CONFIG_FILE"
    echo "temp_min: 55" >> "$CONFIG_FILE"
    echo "temp_high: 65" >> "$CONFIG_FILE"
    echo "temp_max: 85" >> "$CONFIG_FILE"
    print_success "Archivo de configuración creado en $CONFIG_FILE"
fi

# Iniciar menú principal
show_main_menu