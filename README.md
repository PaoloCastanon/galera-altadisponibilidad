# 🚀 Arquitectura de Alta Disponibilidad: MariaDB Galera + HAProxy + Keepalived

Este repositorio contiene la Infraestructura como Código (IaC) y la configuración automatizada para desplegar una arquitectura de alta disponibilidad. Integra un clúster de bases de datos distribuido, balanceo de carga robusto y un mecanismo de IP Virtual (VIP) para garantizar la continuidad del servicio ante fallos.

---

## 📋 Descripción General

El proyecto automatiza el aprovisionamiento (mediante **Terraform**) y la configuración (mediante **Ansible**) de:
- **3 Nodos de Base de Datos distribuidos:** Ejecutando **MariaDB Galera** con replicación sincrónica (`galera1`, `galera2`, `galera3`).
- **2 Nodos de Balanceo de Carga:** Configurados con **HAProxy** para distribuir el tráfico hacia los nodos sanos (`proxy1`, `proxy2`).
- **Manejo de IP Virtual (VIP):** Gestionada por **Keepalived** entre los proxies para ofrecer una puerta de enlace al cliente con *failover* transparente y automático.

---

## 🏗️ Arquitectura del Sistema

```text
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
    │192.168. │                 │192.168│                 │192.168. │
    │122.21   │                 │122.22 │                 │122.23   │
    ├────────┤   Replicación   ├───────┤   Replicación   ├────────┤
    │MariaDB │ ◄──────────────► │MariaDB│ ◄──────────────► │MariaDB │
    │Galera  │    Sincrónica    │Galera │    Sincrónica    │Galera  │
    └────────┘                 └───────┘                 └────────┘
```

---

## 🔧 Requisitos Previos

### Entorno Host (Linux/Debian/Ubuntu)
- **KVM/libvirt** ejecutándose.
- **Terraform** (v1.5+).
- **Ansible** (v2.10+).
- **Claves SSH** en el host (ej. `~/.ssh/id_rsa`).
- Al menos **8 GB de RAM** libre para aprovisionar las 5 máquinas virtuales.

---

## 📦 Instrucciones de Despliegue

### 1. Preparar el entorno (Solo si no tienes KVM/Terraform/Ansible)
```bash
sudo apt-get update && sudo apt-get install -y libvirt-daemon libvirt-clients \
  libvirt-daemon-system terraform ansible openssh-client
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER && newgrp libvirt
```

### 2. Aprovisionar Infraestructura (Terraform)
Esto descargará la imagen base de Debian 12 y levantará las 5 máquinas virtuales.
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 3. Configurar Servicios (Ansible)
Una vez que las VMs están corriendo, provisionamos todo el software y la lógica de clúster.
```bash
cd ../ansible
# Esperar unos segundos a que las VMs inicien su servidor SSH
ansible-playbook -i inventory/hosts.yml playbook.yml
```

---

## 🧪 Testing y Comprobación de Alta Disponibilidad

Hemos incluido scripts diseñados para validar el cumplimiento de todos los objetivos de disponibilidad, balanceo de carga y tolerancia a fallos.

### Ejecutar la Suite de Pruebas de Continuidad
Para testear cómo reacciona la arquitectura y el balanceador al interconectar clientes a través de la VIP, ve a la carpeta raíz y ejecuta:
```bash
./scripts/run-ha-tests.sh
```
> *Nota: Este script es interactivo, evaluará el estado global del ecosistema y te pedirá pausar mientras simulas fallos con las otras herramientas.*

### Monitoreo de Conexión en Tiempo Real
Puedes dejar corriendo un monitor para ver a qué nodo de base de datos se rutea la conexión a través de la IP Virtual en cada segundo:
```bash
./scripts/verify-continuity.sh 192.168.122.10
```

### Herramienta: Simulador de Fallos
Para realizar pruebas controladas de caída de instancias, usa la herramienta de simulación de paradas de servicio:
```bash
# Simular caída de base de datos primaria
./scripts/simulate-failure.sh --node galera1 --action stop

# Simular caída del balanceador de carga Master
./scripts/simulate-failure.sh --node proxy1 --action stop

# Revivir servicios posterior a la prueba
./scripts/simulate-failure.sh --node galera1 --action start
```

---

## ⚙️ Conexión Manual y Dashboards

### Conectarse al clúster de Base de Datos a través de HAProxy
Para simular el flujo que haría una aplicación, conéctate directo a la VIP:
```bash
mysql --skip-ssl -h 192.168.122.10 -u haproxy_check
```

### Panel de Estadísticas (HAProxy Stats)
Puedes visualizar cómo `proxy1` o `proxy2` están realizando el balanceo visitando su panel web:
- **URL:** `http://192.168.122.11:8080/stats`
- **Usuario:** `admin`
- **Contraseña:** `admin123`
