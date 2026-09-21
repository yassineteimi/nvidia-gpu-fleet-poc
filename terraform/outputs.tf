output "control_plane_public_ip" {
  description = "Public address of the control plane. SSH and kubectl from a laptop arrive here."
  value       = scaleway_instance_ip.control_plane.address
}

output "control_plane_private_ip" {
  description = "Reserved private address of the control plane."
  value       = var.control_plane_private_ip
}

output "control_plane_node_ip" {
  description = "Address the control plane kubelet advertises and peers join through."
  value       = local.control_plane_node_ip
}

output "control_plane_name" {
  description = "Kubernetes node name of the control plane."
  value       = local.control_plane_name
}

output "gpu_node_public_ip" {
  description = "Public address of the GPU node, or null when the GPU node is not up."
  value       = var.gpu_node_enabled ? scaleway_instance_ip.gpu_node[0].address : null
}

output "gpu_node_private_ip" {
  description = "Reserved private address of the GPU node."
  value       = var.gpu_node_private_ip
}

output "gpu_node_name" {
  description = "Kubernetes node name of the GPU node."
  value       = local.gpu_node_name
}

output "gpu_node_type" {
  description = "Commercial type of the GPU node, used by the cost report."
  value       = var.gpu_node_type
}

output "gpu_node_enabled" {
  description = "Whether the GPU node is currently declared, and therefore billing."
  value       = var.gpu_node_enabled
}

output "node_ip_mode" {
  description = "Whether cluster traffic runs over the private network or over public addresses."
  value       = var.node_ip_mode
}

output "zone" {
  description = "Zone both nodes run in."
  value       = var.zone
}

output "kubernetes_minor" {
  description = "Kubernetes minor version the apt repository is pinned to."
  value       = var.kubernetes_minor
}

output "ssh_control_plane" {
  description = "Ready made SSH command for the control plane."
  value       = "ssh root@${scaleway_instance_ip.control_plane.address}"
}

output "ssh_gpu_node" {
  description = "Ready made SSH command for the GPU node, or null when it is not up."
  value       = var.gpu_node_enabled ? "ssh root@${scaleway_instance_ip.gpu_node[0].address}" : null
}
