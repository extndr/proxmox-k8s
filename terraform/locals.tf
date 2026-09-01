locals {
  common_tags       = sort(["terraform", "kubernetes", var.cluster_name])
  vm_network_prefix = tonumber(split("/", var.vm_network_cidr)[1])
}
