# Variables
ORIGEN="/home/miguel-notbock/Vídeos/Videos/"
DESTINO="miguel@192.168.1.100:/home/miguel/proyectos/reproductor-casero/src/vid/"

echo "--- Preparando permisos en el servidor ---"
# Esto intenta cambiar los permisos remotamente vía SSH
ssh miguel@192.168.1.100 "sudo chown -R miguel:miguel /home/miguel/proyectos/reproductor-casero/src/vid && sudo chmod -R u+rwx /home/miguel/proyectos/reproductor-casero/src/vid"

if [ $? -eq 0 ]; then
    echo "--- Permisos actualizados, iniciando sincronización ---"
    
    # Ejecución real
    rsync -avzP --delete "$ORIGEN" "$DESTINO"

    if [ $? -eq 0 ]; then
        echo "--- Sincronización finalizada correctamente ---"
    else
        echo "--- Error: Algo falló en la transferencia ---"
    fi
else
    echo "--- Error: No se pudieron cambiar los permisos en el servidor ---"
fi
