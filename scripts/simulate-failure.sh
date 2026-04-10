#!/bin/bash
# =============================================================================
# Script para simular caída de nodos
# Permite detener/iniciar servicios en los nodos para probar alta disponibilidad
# =============================================================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usuarios y claves SSH
SSH_USER="debian"
SSH_KEY="~/.ssh/id_rsa"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q"

# Nodos
declare -A NODES=(
    ["proxy1"]="192.168.122.11"
    ["proxy2"]="192.168.122.12"
    ["galera1"]="192.168.122.21"
    ["galera2"]="192.168.122.22"
    ["galera3"]="192.168.122.23"
)

# Servicios por tipo de nodo
declare -A SERVICES=(
    ["proxy"]="haproxy keepalived"
    ["galera"]="mariadb"
)

# Mostrar ayuda
show_help() {
    echo -e "${BLUE}Uso:${NC} $0 [opciones]"
    echo ""
    echo -e "${YELLOW}Opciones:${NC}"
    echo "  -n, --node <nombre>  Nombre del nodo (proxy1, proxy2, galera1, galera2, galera3)"
    echo "  -a, --action <stop|start|restart|status> Acción a realizar sobre el servicio del nodo"
    echo "  -s, --service <nombre> (Opcional) Especificar un servicio concreto a afectar"
    echo "  -h, --help           Mostrar esta ayuda"
    echo ""
    echo -e "${YELLOW}Ejemplos:${NC}"
    echo "  $0 --node galera1 --action stop"
    echo "  $0 --node proxy2 --action restart"
    echo "  $0 -n proxy1 -a stop -s keepalived"
}

# Parsear argumentos
NODE=""
ACTION=""
SERVICE_OVERRIDE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--node) NODE="$2"; shift ;;
        -a|--action) ACTION="$2"; shift ;;
        -s|--service) SERVICE_OVERRIDE="$2"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Parámetro desconocido: $1"; exit 1 ;;
    esac
    shift
done

# Validar argumentos
if [[ -z "$NODE" || -z "$ACTION" ]]; then
    echo -e "${RED}Error:${NC} Debes especificar un nodo y una acción."
    show_help
    exit 1
fi

if [[ ! "${NODES[$NODE]+isset}" ]]; then
    echo -e "${RED}Error:${NC} Nodo desconocido: $NODE"
    echo "Nodos válidos: ${!NODES[@]}"
    exit 1
fi

case $ACTION in
    stop|start|restart|status) ;;
    *) echo -e "${RED}Error:${NC} Acción inválida. Usa: stop, start, restart, status"; exit 1 ;;
esac

# Determinar servicios
TARGET_IP=${NODES[$NODE]}
TARGET_SERVICES=""

if [[ -n "$SERVICE_OVERRIDE" ]]; then
    TARGET_SERVICES="$SERVICE_OVERRIDE"
else
    if [[ "$NODE" == proxy* ]]; then
        TARGET_SERVICES="${SERVICES[proxy]}"
    elif [[ "$NODE" == galera* ]]; then
        TARGET_SERVICES="${SERVICES[galera]}"
    fi
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Simulador de Fallos - Alta Disponibilidad${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "Nodo:    ${YELLOW}$NODE${NC} ($TARGET_IP)"
echo -e "Acción:  ${YELLOW}$ACTION${NC}"
echo -e "Servicios: ${YELLOW}$TARGET_SERVICES${NC}\n"

for s in $TARGET_SERVICES; do
    echo -e "Ejecutando: ${YELLOW}sudo systemctl $ACTION $s${NC} en $NODE..."
    if ssh $SSH_OPTS -i $SSH_KEY $SSH_USER@$TARGET_IP "sudo systemctl $ACTION $s"; then
        echo -e "${GREEN}[OK]${NC} Servicio $s: $ACTION completado exitosamente."
    else
        echo -e "${RED}[FAIL]${NC} Falla al ejecutar la acción en el servicio $s."
    fi
done

echo -e "\n${BLUE}Verificación posterior recomendada:${NC}"
echo "Ejecuta './scripts/verify-continuity.sh' para revisar el failover."
