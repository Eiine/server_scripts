#!/bin/bash

# Asegurar que FFmpeg esté instalado
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: FFmpeg no está instalado. Instálalo con 'sudo apt install ffmpeg'."
    exit 1
fi

echo "=============================================="
echo "    CONVERTIDOR DE VIDEOS A 720p (MP4/H.264)   "
echo "=============================================="
echo "¿Qué deseas hacer?"
echo "1) Convertir un solo archivo de video"
echo "2) Convertir todos los videos de esta carpeta"
echo "3) Salir"
echo ""
read -p "Selecciona una opción [1-3]: " opcion

# Función para convertir un archivo individual con 1 hilo
convertir_video() {
    local archivo="$1"
    local nombre_base="${archivo%.*}"
    local salida="${nombre_base}_720p.mp4"

    echo ""
    echo "----------------------------------------------"
    echo "Procesando: '$archivo' -> '$salida'"
    echo "Usando un solo hilo de CPU..."
    echo "----------------------------------------------"

    ffmpeg -i "$archivo" \
        -vf "scale=-2:720" \
        -c:v libx264 \
        -preset medium \
        -crf 23 \
        -c:a aac \
        -b:a 128k \
        -threads 1 \
        "$salida"

    echo "¡Listo! Archivo guardado como: $salida"
}

case $opcion in
    1)
        echo ""
        echo "Selecciona el video a convertir:"
        
        # Generar lista de videos en el directorio actual (excluyendo los ya convertidos)
        PS3="Introduce el número del video: "
        
        # Buscar archivos comunes de video
        select archivo in *.mp4 *.mkv *.avi *.mov *.webm; do
            if [ -n "$archivo" ]; then
                convertir_video "$archivo"
                break
            else
                echo "Opción inválida. Intenta nuevamente."
            fi
        done
        ;;
    2)
        echo ""
        echo "Iniciando conversión de TODOS los videos compatibles..."
        
        # Iterar sobre los formatos comunes en la carpeta
        for archivo in *.mp4 *.mkv *.avi *.mov *.webm; do
            # Verificar si el archivo realmente existe (por si no hay de alguna extensión)
            [ -e "$archivo" ] || continue
            
            # Opcional: Evitar re-convertir archivos que ya terminen en _720p.mp4
            if [[ "$archivo" == *_720p.mp4 ]]; then
                continue
            fi

            convertir_video "$archivo"
        done
        
        echo ""
        echo "=============================================="
        echo " ¡Proceso de conversión masiva completado!  "
        echo "=============================================="
        ;;
    3)
        echo "Saliendo..."
        exit 0
        ;;
    *)
        echo "Opción no válida."
        exit 1
        ;;
es-es
