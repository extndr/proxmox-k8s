resource "proxmox_virtual_environment_vm" "k8s_node" {
  for_each = var.nodes

  name        = "k8s-${each.key}"
  description = "${var.cluster_name} Kubernetes ${each.value.role} managed by Terraform"
  node_name   = var.proxmox_node
  vm_id       = each.value.vm_id
  tags        = local.common_tags

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.proxmox_node
    datastore_id = var.vm_datastore
    full         = true
    retries      = 3
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # The bootstrap template uses scsi0 with discard enabled.
  # Repeat non-default disk attributes when resizing cloned disks so provider
  # defaults do not overwrite the template configuration.
  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    discard      = "on"
    size         = each.value.disk_gb
  }

  initialization {
    datastore_id = var.vm_datastore

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${local.vm_network_prefix}"
        gateway = var.gateway
      }
    }

    user_account {
      username = var.ansible_user
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_file)))]
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  started         = true
  stop_on_destroy = true
}
