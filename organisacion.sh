#!/usr/bin/env bash
# ==============================================================================
# Script Name: organizador_videos.sh
# Description: Examina archivos de video en el directorio actual, los agrupa
#              por nombre base eliminando patrones de series, permite elegir
#              una carpeta destino (nueva o existente) y mover los archivos.
# Compatible: Ubuntu Server / Debian (Bash)
# ==============================================================================

# Asegurar que salimos ante errores críticos
set -Eeuo pipefail

# Directorio de trabajo actual
DIRECTORIO_ACTUAL="$(pwd)"
echo "--- Analizando directorio: $DIRECTORIO_ACTUAL ---"
echo ""

# Extensiones de video soportadas
EXTENSIONS=("mp4" "mkv" "avi" "mov" "m4v" "flv" "wmv")

# 1. Recopilar archivos de video de forma segura
declare -a ARCHIVOS=()
while IFS= read -r -d '' archivo; do
    nombre_archivo=$(basename "$archivo")
    ARCHIVOS+=("$nombre_archivo")
done < <(find "$DIRECTORIO_ACTUAL" -maxdepth 1 -type f \( \
    -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o \
    -iname "*.mov" -o -iname "*.m4v" -o -iname "*.flv" -o -iname "*.wmv" \
\) -print0)

if [ ${#ARCHIVOS[@]} -eq 0 ]; then
    echo "No se encontraron archivos de video en este directorio."
    exit 0
fi

# Función para limpiar el nombre base
limpiar_nombre_base() {
    local filename="$1"
    
    # Remover extensión
    local base="${filename%.*0}"
    base="${filename%.*}"
    
    # Aplicar expresiones regulares con sed (compatible con GNU/Linux)
    base=$(echo "$base" | sed -E 's/[sS][0-9]+[eE][0-9]+//g')
    base=$(echo "$base" | sed -E 's/[0-9]{1,2}[xX][0-9]{1,2}//g')
    base=$(echo "$base" | sed -E 's/[eE]p(isodio)?\.?[[:space:]]*[0-9]+//g')
    base=$(echo "$base" | sed -E 's/-[[:space:]]*[0-9]{1,3}$//g')
    
    # Limpiar puntos, guiones o espacios sobrantes al final
    base=$(echo "$base" | sed -E 's/[\.\-_]+$//' | xargs)
    
    # Si queda vacío, usar el nombre original sin extensión
    if [ -z "$base" ]; then
        base="${filename%.*}"
    fi
    
    echo "$base"
}

# 2. Agrupar archivos por nombre base usando un archivo temporal seguro
TEMP_GRUPOS=$(mktemp)
trap 'rm -f "$TEMP_GRUPOS"' EXIT

for f in "${ARCHIVOS[@]}"; do
    base=$(limpiar_nombre_base "$f")
    echo "$base|$f" >> "$TEMP_GRUPOS"
done

# Obtener lista de nombres base únicos ordenados
mapfile -t LISTA_GRUPOS < <(cut -d'|' -f1 "$TEMP_GRUPOS" | sort -u)

echo "Se encontraron ${#ARCHIVOS[@]} archivos de video agrupados en ${#LISTA_GRUPOS[@]} series/categorías:"
echo ""

# Mostrar grupos encontrados y su conteo de archivos
idx=1
for grupo in "${LISTA_GRUPOS[@]}"; do
    archivos_grupo=()
    while IFS='|' read -r b f; do
        if [ "$b" = "$grupo" ]; then
            archivos_grupo+=("$f")
        fi
    done < "$TEMP_GRUPOS"
    
    count=${#archivos_grupo[@]}
    echo "[$idx] $grupo ($count archivos)"
    for f in "${archivos_grupo[@]}"; do
        echo "    - $f"
    done
    echo ""
    ((idx++))
done

# 3. Gestión de la carpeta destino (Crear nueva o usar una existente)
CARPETA_DESTINO="$DIRECTORIO_ACTUAL"

echo "¿Cómo deseas definir la carpeta de destino?"
echo "[1] Usar el directorio actual ($DIRECTORIO_ACTUAL)"
echo "[2] Crear una carpeta nueva"
echo "[3] Indicar la ruta de una carpeta existente"
read -p "Elige una opción (1-3): " opcion_destino
opcion_destino=$(echo "$opcion_destino" | xargs)

case "$opcion_destino" in
    2)
        read -p "Ingresa el nombre para la nueva carpeta: " nombre_carpeta
        nombre_carpeta=$(echo "$nombre_carpeta" | xargs)
        if [ -n "$nombre_carpeta" ]; then
            CARPETA_DESTINO="$DIRECTORIO_ACTUAL/$nombre_carpeta"
            mkdir -p "$CARPETA_DESTINO"
            echo "Carpeta creada exitosamente en: $CARPETA_DESTINO"
        else
            echo "Nombre inválido. Se usará el directorio actual."
        fi
        ;;
    3)
        read -p "Ingresa la ruta absoluta o relativa de la carpeta destino: " ruta_existente
        ruta_existente=$(echo "$ruta_existente" | xargs)
        if [ -d "$ruta_existente" ]; then
            CARPETA_DESTINO="$ruta_existente"
            echo "Carpeta destino establecida en: $CARPETA_DESTINO"
        else
            echo "[AVISO] La ruta no existe o no es un directorio. Se usará el directorio actual."
        fi
        ;;
    *)
        echo "Se usará el directorio actual como destino."
        ;;
esac
echo ""

# 4. Seleccionar qué grupos mover
read -p "Ingresa los números de los grupos que deseas mover (ej: 1,3 o 'todos' para mover todo): " seleccion
seleccion=$(echo "$seleccion" | tr '[:upper:]' '[:lower:]' | xargs)

declare -a GRUPOS_A_MOVER=()

if [ "$seleccion" = "todos" ]; then
    GRUPOS_A_MOVER=("${LISTA_GRUPOS[@]}")
else
    IFS=',' read -ra ADDR <<< "$seleccion"
    for i in "${ADDR[@]}"; do
        i=$(echo "$i" | xargs)
        if [[ "$i" =~ ^[0-9]+$ ]]; then
            index=$((i - 1))
            if [ $index -ge 0 ] && [ $index -lt ${#LISTA_GRUPOS[@]} ]; then
                GRUPOS_A_MOVER+=("${LISTA_GRUPOS[$index]}")
            fi
        fi
    done
fi

if [ ${#GRUPOS_A_MOVER[@]} -eq 0 ]; then
    echo "Selección inválida o vacía. Operación cancelada."
    exit 1
fi

# 5. Ejecutar el movimiento de archivos
echo ""
echo "--- Moviendo archivos ---"

for grupo in "${GRUPOS_A_MOVER[@]}"; do
    while IFS='|' read -r b f; do
        if [ "$b" = "$grupo" ]; then
            origen="$DIRECTORIO_ACTUAL/$f"
            destino="$CARPETA_DESTINO/$f"
            
            # Evitar mover el archivo sobre sí mismo si el destino es el actual
            if [ "$origen" = "$destino" ]; then
                echo "[OMITIDO] El archivo $f ya se encuentra en el directorio destino."
                continue
            fi
            
            # Evitar sobreescritura si ya existe en el destino
            if [ -e "$destino" ]; then
                echo "[AVISO] El archivo $f ya existe en el destino. Se omite."
                continue
            fi
            
            mv "$origen" "$destino"
            echo "[MOVIDO] $f -> $CARPETA_DESTINO/"
        fi
    done < "$TEMP_GRUPOS"
done

echo ""
echo "¡Proceso finalizado con éxito!"
