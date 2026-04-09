variable "base_image_url" {
  description = "URL de la imagen base cloud (Debian 12)"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
}

variable "pool_name" {
  description = "Nombre del storage pool de libvirt"
  type        = string
  default     = "default"
}

variable "network_name" {
  description = "Nombre de la red libvirt"
  type        = string
  default     = "default"
}

variable "ssh_public_key" {
  description = "Clave SSH pública para acceso a las VMs"
  type        = string
  default     = ""
}

# RAM optimizada para 8GB total en el host
# Total VMs: 768 + 1536 = 2.3GB, dejando ~5.7GB para el host
variable "lb_nodes" {
  description = "Configuración de nodos balanceadores"
  type = map(object({
    ip     = string
    memory = number
    vcpu   = number
  }))
  default = {
    proxy1 = { ip = "192.168.122.11", memory = 384, vcpu = 1 }
    proxy2 = { ip = "192.168.122.12", memory = 384, vcpu = 1 }
  }
}

variable "db_nodes" {
  description = "Configuración de nodos de base de datos"
  type = map(object({
    ip     = string
    memory = number
    vcpu   = number
  }))
  default = {
    galera1 = { ip = "192.168.122.21", memory = 512, vcpu = 1 }
    galera2 = { ip = "192.168.122.22", memory = 512, vcpu = 1 }
    galera3 = { ip = "192.168.122.23", memory = 512, vcpu = 1 }
  }
}

variable "vip_address" {
  description = "Dirección IP virtual"
  type        = string
  default     = "192.168.122.10"
}
