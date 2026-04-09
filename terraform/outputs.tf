output "lb_ips" {
  description = "IPs de los balanceadores de carga"
  value = {
    for name, node in var.lb_nodes : name => node.ip
  }
}

output "db_ips" {
  description = "IPs de los nodos de base de datos"
  value = {
    for name, node in var.db_nodes : name => node.ip
  }
}

output "vip_address" {
  description = "Dirección IP virtual"
  value       = var.vip_address
}

output "ssh_connection_examples" {
  description = "Ejemplos de conexión SSH"
  value = <<-EOT
    # Conectar a balanceadores:
    ssh debian@192.168.122.11  # proxy1
    ssh debian@192.168.122.12  # proxy2

    # Conectar a nodos de BD:
    ssh debian@192.168.122.21  # galera1
    ssh debian@192.168.122.22  # galera2
    ssh debian@192.168.122.23  # galera3

    # Conectar a MySQL via VIP:
    mysql --skip-ssl -h 192.168.122.10 -P 3306 -u haproxy_check
  EOT
}
