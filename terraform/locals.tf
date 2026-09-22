locals {
  tags = ["gpu-fleet-poc", var.cluster_name]

  # The key material wins when the scripts supply it. The file path is the
  # fallback for running Terraform by hand, and it is wrapped in try() because
  # Terraform evaluates both branches of a conditional, so an unreadable path
  # would fail even when the material is right there.
  ssh_public_key = trimspace(
    var.ssh_public_key != "" ? var.ssh_public_key : try(file(pathexpand(var.ssh_public_key_path)), "")
  )

  control_plane_name = "${var.cluster_name}-cp-01"
  gpu_node_name      = "${var.cluster_name}-gpu-01"

  public_mode = var.node_ip_mode == "public"

  # The address the kubelet advertises and the address peers reach it on. In
  # private mode this is the IPAM reservation, which is known before the node
  # exists. In public mode it is the flexible IP, which is also known before the
  # node exists because it is reserved as its own resource.
  control_plane_node_ip = local.public_mode ? scaleway_instance_ip.control_plane.address : var.control_plane_private_ip
  gpu_node_node_ip      = local.public_mode ? try(scaleway_instance_ip.gpu_node[0].address, "") : var.gpu_node_private_ip

  # Everything both nodes need before they are anything in particular: a
  # hostname, no swap, the kernel modules and sysctls the kubelet checks for,
  # containerd with the systemd cgroup driver, and a pinned kubeadm toolchain.
  common_bootstrap = {
    kubernetes_minor           = var.kubernetes_minor
    kubernetes_package_version = var.kubernetes_package_version
  }
}
