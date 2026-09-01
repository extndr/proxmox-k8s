mock_provider "proxmox" {}

variables {
  proxmox_endpoint    = "https://pve.test:8006/"
  proxmox_api_token   = "root@pam!terraform=test-token"
  proxmox_insecure    = true
  proxmox_node        = "pve"
  template_vm_id      = 9000
  vm_datastore        = "local-lvm"
  network_bridge      = "vmbr0"
  vm_network_cidr     = "10.10.10.0/24"
  gateway             = "10.10.10.1"
  dns_servers         = ["1.1.1.1", "9.9.9.9"]
  ssh_public_key_file = "tests/fixtures/test.pub"
  ansible_user        = "ubuntu"
  cluster_name        = "lab"

  nodes = {
    cp01 = {
      vm_id   = 201
      role    = "control_plane"
      ip      = "10.10.10.50"
      cores   = 2
      memory  = 3072
      disk_gb = 20
    }
    w01 = {
      vm_id   = 202
      role    = "worker"
      ip      = "10.10.10.51"
      cores   = 2
      memory  = 3072
      disk_gb = 20
    }
  }
}

# Outputs and resource wiring
run "topology_outputs" {
  command = plan

  assert {
    condition     = output.node_names == "k8s-cp01\nk8s-w01"
    error_message = "node_names must expose the canonical Kubernetes node names in sorted order."
  }

  assert {
    condition = (
      output.ansible_inventory.all.children.control_plane.hosts["k8s-cp01"].ansible_host == "10.10.10.50" &&
      output.ansible_inventory.all.children.workers.hosts["k8s-w01"].ansible_host == "10.10.10.51"
    )
    error_message = "Ansible inventory must preserve Terraform node roles and IP addresses."
  }

  assert {
    condition = (
      output.ansible_inventory.all.vars.cluster_name == "lab" &&
      output.ansible_inventory.all.vars.ansible_user == "ubuntu"
    )
    error_message = "Ansible inventory must expose only cross-layer identity needed from Terraform."
  }
}

run "vm_wiring" {
  command = plan

  assert {
    condition = (
      proxmox_virtual_environment_vm.k8s_node["cp01"].name == "k8s-cp01" &&
      proxmox_virtual_environment_vm.k8s_node["cp01"].vm_id == 201 &&
      proxmox_virtual_environment_vm.k8s_node["cp01"].node_name == "pve"
    )
    error_message = "The control-plane VM must use the expected name, VM ID, and Proxmox node."
  }

  assert {
    condition = (
      length(proxmox_virtual_environment_vm.k8s_node) == 2 &&
      proxmox_virtual_environment_vm.k8s_node["w01"].name == "k8s-w01" &&
      proxmox_virtual_environment_vm.k8s_node["w01"].description == "lab Kubernetes worker managed by Terraform"
    )
    error_message = "Terraform must create one VM per node and preserve the node role in VM metadata."
  }
}
