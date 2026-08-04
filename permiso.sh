#!/bin/bash

# 1. Solicitar/aplicar permisos máximos para sí mismo (el propio script)
echo "----------------------------------------------"
echo " Verificando permisos del script..."
echo "----------------------------------------------"
if [ ! -x "$0" ]; then
    echo "Otorgando permisos de ejecución a este script..."
    chmod u+x "$0"
fi

echo "=============================================="
echo "    GESTOR DE PERMISOS TOTALES (777)          "
echo "=============================================="
echo "Este script otorgará permisos totales a archivos."
echo ""

# 2. Listar archivos de la carpeta actual para seleccionar uno
echo "Selecciona el archivo al que deseas darle permisos totales:"
PS3="Introduce el número del archivo: "

select archivo in *; do
    # Validar que se haya seleccionado un elemento válido y que no sea un directorio propio (opcional)
    if [ -n "$archivo" ]; then
        # Evitar modificar el script a sí mismo por seguridad (opcional, pero recomendado)
        if [ "$archivo" == "$(basename "$0")" ]; then
            echo "Aviso: Estás intentando cambiar los permisos de este mismo script."
        fi

        echo ""
        echo "Aplicando permisos totales (777) a: '$archivo'..."
        
        # Aplicar permisos totales (lectura, escritura y ejecución para todos)
        chmod 777 "$archivo"
        
        if [ $? -eq 0 ]; then
            echo "¡Éxito! El archivo '$archivo' ahora tiene permisos totales."
        else
            echo "Hubo un error al cambiar los permisos."
        fi
        break
    else
        echo "Opción inválida. Intenta nuevamente."
    fi
done
