# Galera Alta Disponibilidad

Arquitectura de alta disponibilidad para MariaDB Galera con HAProxy y Keepalived usando libvirt e IaC (Terraform + Ansible).

## 📋 Descripción

Este proyecto automatiza el despliegue de un clúster MariaDB Galera altamente disponible con:
- **3 nodos de base de datos** (`galera1`, `galera2`, `galera3`) con replicación sincrónica Galera
- **2 balanceadores de carga** (`proxy1`, `proxy2`) con HAProxy
- **VIP (Virtual IP)** gestionada por Keepalived para failover automático

## 🏗️ Arquitectura

```
                              ┌─────────────────┐
                              │  Cliente MySQL  │
                              └────────┬────────┘
                                       │
                                     (3306)
                                       │
                    ┌──────────────────┴──────────────────┐
                    │         VIP: 192.168.122.10        │
                    │       (Gestionada por Keepalived)  │
                    └──────────────────┬──────────────────┘
                                       │
              ┌────────────────────────┴────────────────────────┐
              │                                                 │
         ┌────▼─────┐                                   ┌────▼─────┐
         │  proxy1   │ (MASTER)                        │  proxy2   │ (BACKUP)
         │ 192.168.  │                                 │ 192.168.  │
         │ 122.11    │                                 │ 122.12    │
         ├───────────┤                                 ├───────────┤
         │  HAProxy  │                                 │  HAProxy  │
         │Keepalived │                                 │Keepalived │
         └────┬─────┘                                 └────┬─────┘
              │                                             │
        ┌─────┴─────────────────────────────────────────────┴──────┐
        │                                                           │
    ┌───▼────┐                 ┌───────┐                 ┌───▼────┐
    │ galera1 │ ◄──────────────►│galera2│ ◄──────────────► galera3 │
    │192.168. │   (Replicación) │192.168│   (Replicación)│192.168. │
    │122.21   │    Sincrónica   │122.22 │   Sincrónica  │122.23   │
    ├────────┤                 ├───────┤                 ├────────┤
    │MariaDB │                 │MariaDB│                 │MariaDB │
    │Galera  │                 │Galera │                 │Galera  │
    └────────┘                 └───────┘                 └────────┘
```

## 🔧 Requisitos

### Host
- **KVM/libvirt** instalado y ejecutándose
- **Terraform** >= 1.5
- **Ansible** >= 2.10
- **SSH** con acceso por clave pública
- ~8 GB de RAM disponibles para las VMs

### Red
- Red libvirt por defecto o red personalizada
- Rango IP: `192.168.122.0/24`

## 📦 Instalación

### 1. Preparar el host

```bash
# Instalar dependencias (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install -y libvirt-daemon libvirt-clients libvirt-daemon-system \
  terraform ansible openssh-client

# Iniciar libvirtd
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

# Agregar usuario al grupo libvirt
sudo usermod -aG libvirt $USER
newgrp libvirt
```

### 2. Clonar/descargar el repositorio

```bash
cd /path/to/galera-altadisponibilidad
```

### 3. Ejecutar Terraform

```bash
cd terraform

# Inicializar Terraform
terraform init

# Verificar el plan
terraform plan

# Desplegar VMs
terraform apply
```

Esto creará:
- Base image Debian 12
- 5 VMs (proxy1, proxy2, galera1, galera2, galera3)
- Inventario Ansible automático

### 4. Ejecutar Ansible

```bash
cd ../ansible

# Verificar conectividad (opcional)
ansible all -i inventory/hosts.yml -m ping

# Ejecutar el playbook completo
ansible-playbook -i inventory/hosts.yml playbook.yml
```

## ⚙️ Configuración

### Variables principales (ansible/group_vars/all.yml)

```yaml
# VIP
vip_address: "192.168.122.10"
vip_netmask: 24

# Galera
galera_cluster_name: "galera_cluster"
galera_sst_method: "rsync"
mariadb_root_password: "SecureR00tP@ss2024"

# HAProxy
haproxy_stats_port: 8080
haproxy_stats_user: "admin"
haproxy_stats_password: "admin123"

# Keepalived
keepalived_virtual_router_id: 51
keepalived_auth_pass: "k33p@liv3d"
```

### Personalizar nodos

En `terraform/variables.tf`:
```hcl
variable "lb_nodes" {
  default = {
    proxy1 = { ip = "192.168.122.11", memory = 384, vcpu = 1 }
    proxy2 = { ip = "192.168.122.12", memory = 384, vcpu = 1 }
  }
}

variable "db_nodes" {
  default = {
    galera1 = { ip = "192.168.122.21", memory = 512, vcpu = 1 }
    galera2 = { ip = "192.168.122.22", memory = 512, vcpu = 1 }
    galera3 = { ip = "192.168.122.23", memory = 512, vcpu = 1 }
  }
}
```

## 🚀 Uso

### Conexión a las VMs

```bash
# Balanceadores (HAProxy/Keepalived)
ssh debian@192.168.122.11  # proxy1
ssh debian@192.168.122.12  # proxy2

# Nodos de BD (Galera)
ssh debian@192.168.122.21  # galera1
ssh debian@192.168.122.22  # galera2
ssh debian@192.168.122.23  # galera3
```

### Conexión a MySQL

```bash
# Via VIP (recomendado - incluye failover automático)
mysql --skip-ssl -h 192.168.122.10 -u haproxy_check

# Directamente a un nodo
mysql --skip-ssl -h 192.168.122.21 -u haproxy_check
```

### HAProxy Stats

Acceder al panel de estadísticas:
- **URL:** `http://192.168.122.11:8080/stats` (o proxy2)
- **Usuario:** `admin`
- **Contraseña:** `admin123`

## 🧪 Testing y Verificación

### Script de prueba completo

```bash
bash scripts/test-ha.sh
```

El script verifica:
1. ✅ VIP responde
2. ✅ Conexión MySQL via VIP
3. ✅ Estado del clúster Galera
4. ✅ HAProxy backends
5. ✅ Failover de BD (simulado)
6. ✅ Failover de balanceador (simulado)

### Verificaciones manuales

```bash
# Verificar estado de Galera
mysql --skip-ssl -h 192.168.122.10 -u haproxy_check \
  -e "SHOW STATUS LIKE 'wsrep%'"

# Verificar tamaño del clúster
mysql --skip-ssl -h 192.168.122.10 -u haproxy_check \
  -e "SHOW STATUS LIKE 'wsrep_cluster_size'"

# Ver backends de HAProxy
curl -u admin:admin123 \
  http://192.168.122.11:8080/stats;csv | grep mysql_galera

# Verificar VIP en los balanceadores
ssh debian@192.168.122.11 ip addr show
```

## 🔄 Failover

### Failover automático de base de datos

Si un nodo Galera cae:
1. HAProxy lo detecta en ~3 segundos
2. Deja de enviar conexiones a ese nodo
3. Las conexiones se distribuyen entre los otros 2 nodos
4. Cuando el nodo se recupera, se reintegra al clúster automáticamente

### Failover automático de HAProxy/Keepalived

Si `proxy1` (MASTER) cae:
1. Keepalived en `proxy2` lo detecta en ~3 segundos
2. `proxy2` toma la VIP
3. HAProxy en `proxy2` continúa sirviendo conexiones
4. No hay interrupción en el cliente MySQL

## 🛠️ Troubleshooting

### Las VMs no inician

```bash
# Verificar estado de libvirtd
sudo systemctl status libvirtd

# Ver logs de Terraform
cd terraform
terraform apply -verbose
```

### Ansible falla a conectarse

```bash
# Verificar IPs asignadas
virsh domifaddr galera1

# Probar SSH
ssh -i ~/.ssh/id_rsa debian@192.168.122.21 echo OK

# Reintentar inventario
terraform apply -target=local_file.ansible_inventory
```

### Galera no sincroniza

```bash
# Verificar estado en un nodo
ssh debian@192.168.122.21 \
  sudo mysql -e "SHOW STATUS LIKE 'wsrep_%'"

# Para caída catastrófica, editar grastate.dat en el nodo menos avanzado
ssh debian@192.168.122.21 \
  sudo nano /var/lib/mysql/grastate.dat
# Cambiar: safe_to_bootstrap: 1
```

### VIP no flota

```bash
# Verificar Keepalived en proxy1
ssh debian@192.168.122.11 sudo systemctl status keepalived
ssh debian@192.168.122.11 sudo journalctl -u keepalived -n 20

# Verificar dirección actual de VIP
ssh debian@192.168.122.11 ip addr show | grep 192.168.122.10
ssh debian@192.168.122.12 ip addr show | grep 192.168.122.10
```

### HAProxy no ve los backends

```bash
# Verificar HAProxy en un proxy
ssh debian@192.168.122.11 sudo systemctl status haproxy
ssh debian@192.168.122.11 sudo tail -f /var/log/haproxy.log

# Probar conexión directa a Galera
ssh debian@192.168.122.11 \
  mysql --skip-ssl -h 192.168.122.21 -u haproxy_check -e "SELECT 1"
```

## 🧹 Limpieza

### Destruir toda la infraestructura

```bash
cd terraform
terraform destroy
```

## 📊 Monitoreo avanzado

### Crear base de datos de prueba

```bash
mysql --skip-ssl -h 192.168.122.10 -u haproxy_check << 'EOF'
CREATE DATABASE test_ha;
CREATE TABLE test_ha.cluster_test (
  id INT AUTO_INCREMENT PRIMARY KEY,
  hostname VARCHAR(255),
  inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Usuario app (opcional)
CREATE USER 'app'@'%' IDENTIFIED BY 'app_password';
GRANT ALL ON test_ha.* TO 'app'@'%';
EOF
```

### Ver logs de Galera en los nodos

```bash
ssh debian@192.168.122.21 sudo tail -f /var/log/mysql/error.log
ssh debian@192.168.122.21 sudo tail -f /var/log/mysql/mysql.log
```

## 📝 Notas importantes

1. **Contraseñas**: Cambiar las contraseñas por defecto en producción
2. **Firewall**: Puertos 3306 (MySQL), 8080 (HAProxy stats), 4567-4568 (Galera)
3. **SST**: El método `rsync` es lento; considerar `mariabackup` en producción
4. **Backups**: Implementar estrategia de backups periódicos
5. **Monitoreo**: Integrar con Prometheus/Grafana para alertas

## 📚 Referencias

- [MariaDB Galera Cluster](https://mariadb.com/kb/en/mariadb-galera-cluster/)
- [HAProxy](http://www.haproxy.org/)
- [Keepalived](https://www.keepalived.org/)
- [Terraform Libvirt Provider](https://github.com/dmacvicar/terraform-provider-libvirt)

## 📄 Licencia

Este proyecto está disponible bajo la licencia MIT.

---

**Última actualización:** 2026-04-08
