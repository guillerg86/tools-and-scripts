#!/bin/bash

#######################################################################################
# @author: Guille Rodriguez https://github.com/guillerg86
#
# Obtiene las particiones de un dispositivo USB a través del VendorID y ProductID del 
# dispositivo y las formatea en tipo exFAT. Permitiendo sanitizar un USB antes de 
# que sea conectado a un sistema Windows. 
#
#######################################################################################


COLOR_YELLOW='\033[0;33m'
COLOR_RESET='\033[0m'
TIME_SLEEP=5
PART_FORMAT_RGX="[h|s]{1}d[a-z]{1}[0-9]{1}$"

## Recibimos el VENDOR_ID y el PRODUCT_ID (por ejemplo 0930:6545)
vidpid=$1

## Comprobamos el formato, si no cuadra... no hacemos nada
if ! [[ $vidpid =~ ^[0-9]{4}:[0-9]{4}$ ]]; then
	echo -e "${COLOR_YELLOW}El VIDPID $vidpid no tiene un formato esperado${COLOR_RESET}"
	exit 1;
fi

## Separamos el VID y el PID
arrVIDPID=(${vidpid//:/ })
vid=${arrVIDPID[0]}
pid=${arrVIDPID[1]}

#echo "VID: $vid"
#echo "PID: $pid"

# Intentamos obtener las particiones en caso de ser un dispositivo de storage
partitions=`udevadm trigger -v -n -s block -p ID_VENDOR_ID=$vid -p ID_MODEL_ID=$pid | egrep -o $PART_FORMAT_RGX`
if [ ${#partitions[@]} -eq 0 ]; then
	echo -e "${COLOR_YELLOW}No se han detectado particiones en el dispositivo usb con VID=$vid y PID=$pid ${COLOR_RESET}"
	echo -e "${COLOR_YELLOW}Ignorando el dispositivo conectado${COLOR_RESET}"
	exit 1;
fi

# Listamos las particiones existentes en el dispositivo y desmontamos las unidades
for partition in $partitions; 
do
	echo -e "Detectada particion con identificador ${COLOR_YELLOW}$partition${COLOR_RESET}"
	umount /dev/$partition 2> /dev/null
done

# Mostramos mensaje de warning al usuario, si no quiere que el storage se borre, que lo retire YA!
echo -e "${COLOR_YELLOW}Si no quieres que se borre el contenido retira YA! el dispositivo!!!!${COLOR_RESET}"
echo -e "${COLOR_YELLOW}Se inicia el formateo del dispositivo $device a formato EXTFAT en $TIME_SLEEP segundos${COLOR_RESET}"

sleep $TIME_SLEEP

for partition in $partitions;
do
	# Si alguna de las particiones no existe ignoramos la particion
	# Si lo ha retirado, no existirá ninguna
	if [ -b /dev/$partition ]; then
		echo " "
		echo "------------------------------------------------"
		echo "Formateando particion $partition"
		echo "------------------------------------------------"
		mkfs.exfat /dev/$partition
		echo "------------------------------------------------"
	else
		echo "No existe la particion /dev/$partition. La has retirado? Se aborta el proceso de limpieza de disco"
	fi
done

echo "YA PUEDE RETIRAR EL DISPOSITIVO"
