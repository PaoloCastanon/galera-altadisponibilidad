#!/bin/bash
# =============================================================================
# Script de Prueba de Alta Disponibilidad
# Demuestra el failover del clúster MariaDB Galera + HAProxy + Keepalived
# =============================================================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
VIP="192.168.122.10"
MYSQL_USER="haproxy_check"
MYSQL_PASS=""
MYSQL_SSL_OPTS="--skip-ssl"
HAPROXY_STATS_USER="admin"
HAPROXY_STATS_PASS="admin123"

# Nodos
LB1="192.168.122.11"
LB2="192.168.122.12"
DB1="192.168.122.21"
DB2="192.168.122.22"
DB3="192.168.122.23"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Prueba de Alta Disponibilidad${NC}"
echo -e "${BLUE}============================================${NC}"

# Función para verificar conexión MySQL
test_mysql() {
    local host=$1
    local description=$2
    local auth=""
    if [ -n "$MYSQL_PASS" ]; then
        auth="-p$MYSQL_PASS"
    fi
    echo -e "\n${YELLOW}[TEST]${NC} $description"
    if mysql $MYSQL_SSL_OPTS -h "$host" -u "$MYSQL_USER" $auth -e "SELECT 1;" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Conexión exitosa a $host"
        return 0
    else
        echo -e "${RED}[FAIL]${NC} No se pudo conectar a $host"
        return 1
    fi
}

# Función para verificar VIP
check_vip() {
    echo -e "\n${YELLOW}[TEST]${NC} Verificando VIP ($VIP)"
    if ping -c 1 -W 2 "$VIP" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} VIP $VIP responde"
        return 0
    else
        echo -e "${RED}[FAIL]${NC} VIP $VIP no responde"
        return 1
    fi
}

# Función para verificar estado de Galera
check_galera_status() {
    local host=$1
    local auth=""
    if [ -n "$MYSQL_PASS" ]; then
        auth="-p$MYSQL_PASS"
    fi
    echo -e "\n${YELLOW}[TEST]${NC} Estado del clúster Galera via $host"

    local cluster_size=$(mysql $MYSQL_SSL_OPTS -h "$host" -u "$MYSQL_USER" $auth -N -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print $2}')
    local cluster_status=$(mysql $MYSQL_SSL_OPTS -h "$host" -u "$MYSQL_USER" $auth -N -e "SHOW STATUS LIKE 'wsrep_cluster_status';" 2>/dev/null | awk '{print $2}')
    local local_state=$(mysql $MYSQL_SSL_OPTS -h "$host" -u "$MYSQL_USER" $auth -N -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | awk '{print $2}')

    echo -e "${GREEN}  Tamaño del clúster: ${NC}$cluster_size nodos"
    echo -e "${GREEN}  Estado del clúster: ${NC}$cluster_status"
    echo -e "${GREEN}  Estado local:       ${NC}$local_state"
}

# Función para verificar HAProxy
check_haproxy() {
    local host=$1
    echo -e "\n${YELLOW}[TEST]${NC} Estado de HAProxy en $host"

    if curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASS" "http://$host:8080/stats;csv" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} HAProxy stats accesible en http://$host:8080/stats"

        # Mostrar estado de backends
        echo -e "${BLUE}  Backends MySQL:${NC}"
        curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASS" "http://$host:8080/stats;csv" | \
            grep "mysql_galera" | grep -v "FRONTEND\|BACKEND" | \
            awk -F',' '{printf "    %s: %s\n", $2, $18}'
    else
        echo -e "${RED}[FAIL]${NC} HAProxy no accesible en $host"
    fi
}

# Función para insertar datos de prueba
insert_test_data() {
    local auth=""
    if [ -n "$MYSQL_PASS" ]; then
        auth="-p$MYSQL_PASS"
    fi
    echo -e "\n${YELLOW}[TEST]${NC} Insertando datos de prueba via VIP"
    mysql $MYSQL_SSL_OPTS -h "$VIP" -u "$MYSQL_USER" $auth -e "
        INSERT INTO test_ha.cluster_test (hostname) VALUES ('$(hostname)');
        SELECT * FROM test_ha.cluster_test ORDER BY id DESC LIMIT 5;
    " 2>/dev/null
    echo -e "${GREEN}[OK]${NC} Datos insertados y verificados"
}

# Función para simular caída de nodo
simulate_node_failure() {
    local node=$1
    echo -e "\n${RED}============================================${NC}"
    echo -e "${RED}  SIMULANDO CAÍDA DE NODO: $node${NC}"
    echo -e "${RED}============================================${NC}"
    echo -e "${YELLOW}Para simular la caída, ejecuta en otra terminal:${NC}"
    echo -e "  ssh debian@$node 'sudo systemctl stop mariadb'  # Para nodo DB"
    echo -e "  ssh debian@$node 'sudo systemctl stop haproxy'  # Para nodo LB"
    echo -e ""
    echo -e "${YELLOW}Presiona ENTER cuando hayas detenido el servicio...${NC}"
    read
}

# =============================================================================
# EJECUCIÓN DE PRUEBAS
# =============================================================================

echo -e "\n${BLUE}1. VERIFICACIÓN INICIAL${NC}"
echo -e "${BLUE}------------------------${NC}"

check_vip
test_mysql "$VIP" "Conexión a MySQL via VIP"
check_galera_status "$VIP"
check_haproxy "$LB1"

echo -e "\n${BLUE}2. PRUEBA DE ESCRITURA/LECTURA${NC}"
echo -e "${BLUE}-------------------------------${NC}"
insert_test_data

echo -e "\n${BLUE}3. PRUEBA DE FAILOVER DE BASE DE DATOS${NC}"
echo -e "${BLUE}---------------------------------------${NC}"

echo -e "${YELLOW}Apaga uno de los nodos de BD (galera1, galera2, o galera3)${NC}"
simulate_node_failure "galera1"

echo -e "\n${YELLOW}[VERIFICANDO]${NC} Estado después de caída de nodo..."
sleep 3
check_galera_status "$VIP"
test_mysql "$VIP" "Conexión a MySQL via VIP (después de failover)"
insert_test_data

echo -e "\n${BLUE}4. PRUEBA DE FAILOVER DE BALANCEADOR${NC}"
echo -e "${BLUE}-------------------------------------${NC}"

echo -e "${YELLOW}Apaga el balanceador MASTER (proxy1)${NC}"
simulate_node_failure "proxy1"

echo -e "\n${YELLOW}[VERIFICANDO]${NC} Estado después de caída de balanceador..."
sleep 5
check_vip
test_mysql "$VIP" "Conexión a MySQL via VIP (después de failover LB)"
check_haproxy "$LB2"

echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}  PRUEBAS COMPLETADAS${NC}"
echo -e "${BLUE}============================================${NC}"

echo -e "\n${YELLOW}Resumen:${NC}"
echo "- VIP: $VIP"
echo "- HAProxy Stats: http://$LB1:8080/stats (user: $HAPROXY_STATS_USER)"
echo "- MySQL via VIP: mysql -h $VIP -u $MYSQL_USER -p"
echo ""
echo -e "${GREEN}La arquitectura de alta disponibilidad está funcionando correctamente.${NC}"
