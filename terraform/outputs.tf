output "ansible_inventory" {
  description = "Static Ansible inventory derived from the Terraform lab topology"
  value = {
    all = {
      vars = {
        ansible_user               = var.ansible_user
        ansible_python_interpreter = "/usr/bin/python3"
        cluster_name               = var.cluster_name
      }
      children = {
        control_plane = {
          hosts = {
            for name, node in var.nodes : "k8s-${name}" => {
              ansible_host = node.ip
            } if node.role == "control_plane"
          }
        }
        workers = {
          hosts = {
            for name, node in var.nodes : "k8s-${name}" => {
              ansible_host = node.ip
            } if node.role == "worker"
          }
        }
      }
    }
  }
}

output "node_names" {
  description = "Newline-separated Kubernetes node names used by the smoke test"
  value = join("\n", sort([
    for name in keys(var.nodes) : "k8s-${name}"
  ]))
}
