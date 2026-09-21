########################################
# Control plane node
#
# Persistent. It holds etcd, the control plane, ArgoCD and, from Session B,
# kube-prometheus-stack. It outlives the GPU node on purpose: the goodput and
# burn-in work in Session D compares metrics across sessions a week apart, and a
# Prometheus that resets every time the GPU node is destroyed cannot answer that.
########################################

resource "scaleway_instance_ip" "control_plane" {
  type = "routed_ipv4"
  tags = local.tags
}

resource "scaleway_instance_server" "control_plane" {
  name              = local.control_plane_name
  type              = var.control_plane_type
  image             = var.control_plane_image
  security_group_id = scaleway_instance_security_group.control_plane.id
  ip_id             = scaleway_instance_ip.control_plane.id
  tags              = concat(local.tags, ["control-plane"])

  root_volume {
    size_in_gb            = var.control_plane_root_volume_size_gb
    volume_type           = var.root_volume_type
    delete_on_termination = true
  }

  user_data = {
    cloud-init = templatefile("${path.module}/cloud-init/control-plane.sh.tftpl", {
      common = templatefile("${path.module}/cloud-init/common.sh.tftpl", merge(local.common_bootstrap, {
        node_name            = local.control_plane_name
        node_ip              = local.control_plane_node_ip
        private_ip           = var.control_plane_private_ip
        private_prefix       = split("/", var.private_network_subnet)[1]
        private_nic_required = !local.public_mode
      }))

      node_name       = local.control_plane_name
      node_ip         = local.control_plane_node_ip
      private_ip      = var.control_plane_private_ip
      public_ip       = scaleway_instance_ip.control_plane.address
      cluster_name    = var.cluster_name
      pod_subnet      = var.pod_subnet
      service_subnet  = var.service_subnet
      flannel_version = var.flannel_version
    })
  }

  lifecycle {
    # The bootstrap script only runs on first boot. Rendering differences after
    # the cluster exists must not silently rebuild the control plane and take
    # etcd with them. Change the script deliberately, then taint and replace.
    ignore_changes = [user_data]
  }

  depends_on = [scaleway_iam_ssh_key.admin]
}

resource "scaleway_instance_private_nic" "control_plane" {
  server_id          = scaleway_instance_server.control_plane.id
  private_network_id = scaleway_vpc_private_network.main.id
  ipam_ip_ids        = [scaleway_ipam_ip.control_plane.id]
  tags               = local.tags

  depends_on = [scaleway_ipam_ip.control_plane]
}
