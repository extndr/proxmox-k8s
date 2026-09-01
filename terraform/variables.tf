variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in USER@REALM!TOKENID=SECRET format. Provide it via TF_VAR_proxmox_api_token (normally from .env)."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip Proxmox API TLS verification for a self-signed lab certificate"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "template_vm_id" {
  description = "VM ID of the reusable Ubuntu cloud-init template"
  type        = number
  default     = 9000

  validation {
    condition = (
      floor(var.template_vm_id) == var.template_vm_id &&
      var.template_vm_id >= 100 && var.template_vm_id <= 999999999
    )
    error_message = "template_vm_id must be an integer between 100 and 999999999."
  }
}

variable "vm_datastore" {
  type    = string
  default = "local-lvm"
}

variable "network_bridge" {
  description = "Existing Proxmox Linux bridge or VNet attached to the Kubernetes VMs"
  type        = string
  default     = "vmbr0"
}

variable "vm_network_cidr" {
  description = "IPv4 CIDR of the existing Proxmox network used by the Kubernetes VMs; Terraform configures VM addresses on this network but does not create the upstream network"
  type        = string

  validation {
    condition = try(
      cidrnetmask(var.vm_network_cidr) != "" &&
      split("/", var.vm_network_cidr)[0] == cidrhost(var.vm_network_cidr, 0),
      false
    )
    error_message = "vm_network_cidr must be a canonical IPv4 network CIDR, for example 10.10.10.0/24."
  }
}

variable "gateway" {
  description = "Default IPv4 gateway for Kubernetes VMs"
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.gateway}/32"))
    error_message = "gateway must be a valid IPv4 address without a CIDR prefix."
  }
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "9.9.9.9"]
}

variable "ssh_public_key_file" {
  description = "Public SSH key injected into VM cloud-init user data"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ansible_user" {
  description = "OS user created by cloud-init and used by Ansible"
  type        = string
  default     = "ubuntu"
}

variable "cluster_name" {
  description = "Lab identity used in Proxmox metadata and passed to Ansible"
  type        = string
  default     = "lab"
}

variable "nodes" {
  description = "Kubernetes VM definitions"
  type = map(object({
    vm_id   = number
    role    = string
    ip      = string
    cores   = number
    memory  = number
    disk_gb = number
  }))

  validation {
    condition     = length([for _, node in var.nodes : node if node.role == "control_plane"]) == 1
    error_message = "Exactly one node must have role = control_plane."
  }

  validation {
    condition     = alltrue([for _, node in var.nodes : contains(["control_plane", "worker"], node.role)])
    error_message = "Node role must be control_plane or worker."
  }

  validation {
    condition = alltrue([
      for name in keys(var.nodes) :
      length(name) <= 59 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", name))
    ])
    error_message = "Node map keys must be lowercase DNS-label-compatible names up to 59 characters; the lab prefixes them with k8s-."
  }

  validation {
    condition = (
      length(distinct([for _, node in var.nodes : node.vm_id])) == length(var.nodes) &&
      length(distinct([for _, node in var.nodes : node.ip])) == length(var.nodes)
    )
    error_message = "VM IDs and node IPs must be unique."
  }

  validation {
    condition     = alltrue([for _, node in var.nodes : node.ip != var.gateway])
    error_message = "A node IP must not be the same as the default gateway."
  }

  validation {
    condition     = alltrue([for _, node in var.nodes : node.vm_id != var.template_vm_id])
    error_message = "Node VM IDs must not reuse template_vm_id."
  }

  validation {
    condition = alltrue([
      for _, node in var.nodes :
      floor(node.vm_id) == node.vm_id &&
      node.vm_id >= 100 && node.vm_id <= 999999999 &&
      floor(node.cores) == node.cores && node.cores >= 1 &&
      floor(node.memory) == node.memory && node.memory >= 1 &&
      floor(node.disk_gb) == node.disk_gb && node.disk_gb >= 12 &&
      try(cidrnetmask("${node.ip}/32") != "", false)
    ])
    error_message = "Each node needs an integer VM ID between 100 and 999999999, a valid IPv4 address, positive integer CPU/memory values, and disk_gb >= 12 (the base template disk size)."
  }

  validation {
    condition = try(
      cidrhost("${var.gateway}/${split("/", var.vm_network_cidr)[1]}", 0) == cidrhost(var.vm_network_cidr, 0) &&
      var.gateway != cidrhost(var.vm_network_cidr, 0) &&
      var.gateway != cidrhost(var.vm_network_cidr, -1) &&
      alltrue([
        for _, node in var.nodes :
        cidrhost("${node.ip}/${split("/", var.vm_network_cidr)[1]}", 0) == cidrhost(var.vm_network_cidr, 0) &&
        node.ip != cidrhost(var.vm_network_cidr, 0) &&
        node.ip != cidrhost(var.vm_network_cidr, -1)
      ]),
      false
    )
    error_message = "gateway and all node IPs must be usable host addresses inside vm_network_cidr."
  }
}
