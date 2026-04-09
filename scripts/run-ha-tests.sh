#!/bin/bash
# =============================================================================
# Suite de Pruebas de Alta Disponibilidad
# Verifica el failover del clúster MariaDB Galera + HAProxy + Keepalived
# =============================================================================

set -e

# Configuración de Colores
C_TITLE='\033[1;36m'   # Cyan Bold
C_STEP='\033[1;35m'    # Purple Bold
C_SUCCESS='\033[1;32m' # Green Bold
C_WARN='\033[1;33m'    # Yellow Bold
C_ERROR='\033[1;31m'   # Red Bold
C_INFO='\033[1;34m'    # Blue Bold
C_RESET='\033[0m'      # Reset

# Configuración de Variables
VIP="192.168.122.10"
MYSQL_USER="haproxy_check"
MYSQL_PASS=""
MYSQL_SSL_OPTS="--skip-ssl"
HAPROXY_STATS_USER="admin"
HAPROXY_STATS_PASS="admin123"

# Nodos
LB1="192.168.122.11"
LB2="192.168.122.12"

# -----------------------------------------------------------------------------
# Funciones Auxiliares de Formato
# -----------------------------------------------------------------------------
print_title() {
    echo -e "\n${C_TITLE}╔════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_TITLE}║ $1 │${C_RESET}"
    echo -e "${C_TITLE}╚════════════════════════════════════════════════════════════════╝${C_RESET}\n"
}

print_step() {
    echo -e "${C_STEP}▶ [Paso]${C_RESET} $1"
}

print_ok() {
    echo -e "   ${C_SUCCESS}✓ $1${C_RESET}"
}

print_fail() {
    echo -e "   ${C_ERROR}✗ $1${C_RESET}"
}

print_info() {
    echo -e "   ${C_INFO}• $1${C_RESET}"
}

# -----------------------------------------------------------------------------
# Tests de Componentes
# -----------------------------------------------------------------------------

test_mysql() {
    local host=$1
    local desc=$2
    local auth=${MYSQL_PASS:+"-p$MYSQL_PASS"}
    
    print_step "$desc"
    if mysql $MYSQL_SSL_OPTS -h "$host" -u "$MYSQL_USER" $auth -e "SELECT 1;" &>/dev/null; then
        print_ok "Conexión MySQL establecida contra $host"
        return 0
    else
        print_fail "Fallo al conectar a MySQL en $host"
        return 1
    fi
}

check_vip() {
    print_step "Verificando disponibilidad de la IP Virtual ($VIP)"
    if ping -c 1 -W 2 "$VIP" &>/dev/null; then
        print_ok "La IP Virtual ($VIP) responde al PING"
        return 0
    else
        print_fail "La IP Virtual ($VIP) NO responde"
        return 1
    fi
}

check_galera_status() {
    local host=$1
    local auth=${MYSQL_PASS:+"-p$MYSQL_PASS"}
    
    print_step "Consultando estado interno de Galera en $host"

    local cluster_size=$(mysql $MYSQL_SSL_OPTS -h "$host" -u "$MYSQL_USER" $auth -N -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print $2}')
    local cluster_status=$(mysql $MYSQL_SSL_OPTS -h "$host" -u "$MYSQL_USER" $auth -N -e "SHOW STATUS LIKE 'wsrep_cluster_status';" 2>/dev/null | awk '{print $2}')
    local local_state=$(mysql $MYSQL_SSL_OPTS -h "$host" -u "$MYSQL_USER" $auth -N -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | awk '{print $2}')

    print_info "Tamaño del clúster: ${cluster_size} nodos activos"
    print_info "Estado en el clúster: ${cluster_status}"
    print_info "Estado local de replica: ${local_state}"
}

check_haproxy() {
    local host=$1
    print_step "Verificando backend de HAProxy en $host"

    if curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASS" "http://$host:8080/stats;csv" &>/dev/null; then
        print_ok "Portal de estadísticas accesible en http://$host:8080/stats"
        print_info "Estado de los backends de DB (mysql_galera):"
        
        # Muestra el estado del backend de un CSV simple
        curl -s -u "$HAPROXY_STATS_USER:$HAPROXY_STATS_PASS" "http://$host:8080/stats;csv" | \
            grep "mysql_galera" | grep -v "FRONTEND\|BACKEND" | \
            awk -F',' '{printf "       - Nodo %s: %s\n", $2, $18}'
    else
        print_fail "No se puede acceder a las estadísticas de HAProxy en $host"
    fi
}

# -----------------------------------------------------------------------------
# Funciones Interactivas
# -----------------------------------------------------------------------------

simulate_node_failure() {
    local node=$1
    local action=${2:-"caída"}
    
    echo -e "\n${C_WARN}⚠️  INTERACCIÓN REQUERIDA: Simular $action del nodo $node${C_RESET}"
    echo -e "   Abre otra terminal y ejecuta el script de simulación:"
    echo -e "   ${C_INFO}./scripts/simulate-failure.sh --node $node --action stop${C_RESET}\n"
    
    read -p "$(echo -e ${C_WARN}➜ Presiona ENTER tras haber apagado el componente en $node...${C_RESET})"
}

# =============================================================================
# EJECUCIÓN DEL FLUJO DE PRUEBAS
# =============================================================================

clear
print_title "Suite de Pruebas de Alta Disponibilidad - Galera & HAProxy"

echo -e "\n${C_TITLE}====== FASE 1: Verificación del Estado Base ======${C_RESET}"
check_vip
test_mysql "$VIP" "Prueba de conexión genérica MySQL (Vía VIP)"
check_galera_status "$VIP"
check_haproxy "$LB1"

echo -e "\n${C_TITLE}====== FASE 2: Failover de Base de Datos ======${C_RESET}"
simulate_node_failure "galera1" "caída del servidor de base de datos primario"

echo -e "⏳ Analizando recuperación post-incidente..."
sleep 3
check_galera_status "$VIP"
test_mysql "$VIP" "Conexión MySQL Vía VIP tras apagar el nodo Galera"

echo -e "\n${C_TITLE}====== FASE 3: Failover de Balanceador (HAProxy) ======${C_RESET}"
simulate_node_failure "proxy1" "caída del balanceador de carga Master"

echo -e "⏳ Analizando toma de control por parte del proxy Back-up..."
sleep 5
check_vip
test_mysql "$VIP" "Conexión MySQL Vía VIP tras migración de IP"
check_haproxy "$LB2"

print_title "✅ FINALIZADO: Comprobaciones de continuidad completadas"
