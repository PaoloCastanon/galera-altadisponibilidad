#!/bin/bash
# Verifica la continuidad del servicio consultando la base de datos en bucle a través de la VIP o HAProxy

if [ "$#" -lt 1 ]; then
    echo "Uso: $0 <VIP_o_IP_del_HAProxy> [usuario] [password]"
    echo "Ejemplo: $0 192.168.1.100 myuser mypassword"
    exit 1
fi

VIP=$1
USER=${2:-"haproxy_check"}
PASS=${3:-""} 

echo "Iniciando monitor de continuidad hacia $VIP..."
echo "Asegúrate de tener el cliente 'mysql' o 'mariadb' instalado localmente."
echo "Presiona Ctrl+C para detener."
echo "------------------------------------------------------"

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Intenta obtener el nombre del nodo que responde la consulta (útil si pasamos por HAProxy)
    if [ -z "$PASS" ]; then
        RESULT=$(mysql --skip-ssl -h "$VIP" -u "$USER" -e "SHOW VARIABLES LIKE 'wsrep_node_name';" -E 2>/dev/null)
    else
        RESULT=$(mysql --skip-ssl -h "$VIP" -u "$USER" -p"$PASS" -e "SHOW VARIABLES LIKE 'wsrep_node_name';" -E 2>/dev/null)
    fi
    
    if [ $? -eq 0 ]; then
        # Parsear el valor de la variable de MariaDB
        NODE_NAME=$(echo "$RESULT" | grep "Value:" | awk '{print $2}')
        echo "[$TIMESTAMP] ✅ ÉXITO: Conexión establecida. Respondido por el nodo: ${NODE_NAME:-Desconocido}"
    else
        echo "[$TIMESTAMP] ❌ FALLO: No se pudo conectar a la base de datos."
    fi
    
    # Pausa de 1 segundo entre verificaciones
    sleep 1
done
