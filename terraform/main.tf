# Obtener la clave SSH del usuario si no se proporciona
locals {
  ssh_key   = var.ssh_public_key != "" ? var.ssh_public_key : file("~/.ssh/id_rsa.pub")
  all_nodes = merge(var.lb_nodes, var.db_nodes)
}

# Imagen base para todas las VMs (Debian 12)
resource "libvirt_volume" "base_image" {
  name   = "debian-12-base.qcow2"
  pool   = var.pool_name
  source = var.base_image_url
  format = "qcow2"
}

# Volúmenes para cada VM (clonados de la imagen base)
resource "libvirt_volume" "vm_disk" {
  for_each = local.all_nodes

  name           = "${each.key}-disk.qcow2"
  pool           = var.pool_name
  base_volume_id = libvirt_volume.base_image.id
  size           = 5368709120 # 5GB (>= base image size)
  format         = "qcow2"
}

# Cloud-init para configuración inicial (Debian 12)
resource "libvirt_cloudinit_disk" "vm_cloudinit" {
  for_each = local.all_nodes

  name = "${each.key}-cloudinit.iso"
  pool = var.pool_name

  user_data = <<-EOF
    #cloud-config
    hostname: ${each.key}
    fqdn: ${each.key}.local
    manage_etc_hosts: true

    users:
      - name: debian
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - ${local.ssh_key}

    ssh_pwauth: false
    disable_root: false

    packages:
      - python3
      - sudo
      - openssh-server
      - qemu-guest-agent

    runcmd:
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
      - systemctl restart ssh

    final_message: "VM ${each.key} lista en $UPTIME segundos"
  EOF

  network_config = <<-EOF
    version: 2
    ethernets:
      ens3:
        dhcp4: false
        addresses:
          - ${each.value.ip}/24
        gateway4: 192.168.122.1
        nameservers:
          addresses:
            - 192.168.122.1
            - 8.8.8.8
  EOF
}

# Definición de las VMs
resource "libvirt_domain" "vm" {
  for_each = local.all_nodes

  name   = each.key
  memory = each.value.memory
  vcpu   = each.value.vcpu

  cloudinit = libvirt_cloudinit_disk.vm_cloudinit[each.key].id

  network_interface {
    network_name   = var.network_name
    wait_for_lease = false # IPs estáticas via cloud-init
  }

  disk {
    volume_id = libvirt_volume.vm_disk[each.key].id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  qemu_agent = false # Deshabilitamos para evitar problemas de espera
}

# Esperar a que las VMs estén listas (con timeout y reintentos)
resource "null_resource" "wait_for_vms" {
  for_each = local.all_nodes

  depends_on = [libvirt_domain.vm]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Esperando a ${each.key} (${each.value.ip})..."
      for i in $(seq 1 10); do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ~/.ssh/id_rsa debian@${each.value.ip} 'echo OK' 2>/dev/null; then
          echo "${each.key} está lista!"
          exit 0
        fi
        echo "Intento $i/30 - esperando..."
        sleep 5
      done
      echo "Timeout esperando ${each.key}"
      exit 1
    EOT
  }
}

# Generar inventario de Ansible automáticamente
resource "local_file" "ansible_inventory" {
  depends_on = [null_resource.wait_for_vms]

  filename = "${path.module}/../ansible/inventory/hosts.yml"
  content  = <<-EOF
    all:
      vars:
        ansible_user: debian
        ansible_ssh_private_key_file: ~/.ssh/id_rsa
        ansible_python_interpreter: /usr/bin/python3
      children:
        loadbalancers:
          hosts:
%{for name, node in var.lb_nodes~}
            ${name}:
              ansible_host: ${node.ip}
%{endfor~}
        databases:
          hosts:
%{for name, node in var.db_nodes~}
            ${name}:
              ansible_host: ${node.ip}
%{endfor~}
  EOF
}
