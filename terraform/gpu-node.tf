########################################
# GPU node
#
# Ephemeral by design. Created at the start of a session by scripts/gpu-up.sh
# and destroyed at the end by scripts/gpu-down.sh, which is both a cost control
# and a rehearsal: the drain and remove path the remediation controller uses in
# Session C is the same path every session teardown takes.
#
# gpu_node_enabled defaults to false so that a plain terraform apply can never
# leave an L4 running by accident.
########################################

resource "scaleway_instance_ip" "gpu_node" {
  count = var.gpu_node_enabled ? 1 : 0

  type = "routed_ipv4"
  tags = local.tags
}

resource "scaleway_instance_server" "gpu_node" {
  count = var.gpu_node_enabled ? 1 : 0

  name              = local.gpu_node_name
  type              = var.gpu_node_type
  image             = var.gpu_node_image
  security_group_id = scaleway_instance_security_group.gpu_node.id
  ip_id             = scaleway_instance_ip.gpu_node[0].id
  tags              = concat(local.tags, ["gpu-node"])

  root_volume {
    size_in_gb            = var.gpu_node_root_volume_size_gb
    volume_type           = var.root_volume_type
    delete_on_termination = true
  }

  user_data = {
    cloud-init = templatefile("${path.module}/cloud-init/gpu-node.sh.tftpl", {
      common = templatefile("${path.module}/cloud-init/common.sh.tftpl", merge(local.common_bootstrap, {
        node_name            = local.gpu_node_name
        node_ip              = local.gpu_node_node_ip
        private_ip           = var.gpu_node_private_ip
        private_prefix       = split("/", var.private_network_subnet)[1]
        private_nic_required = !local.public_mode
      }))
    })
  }

  depends_on = [scaleway_iam_ssh_key.admin]
}

resource "scaleway_instance_private_nic" "gpu_node" {
  count = var.gpu_node_enabled ? 1 : 0

  server_id          = scaleway_instance_server.gpu_node[0].id
  private_network_id = scaleway_vpc_private_network.main.id
  ipam_ip_ids        = [scaleway_ipam_ip.gpu_node[0].id]
  tags               = local.tags

  depends_on = [scaleway_ipam_ip.gpu_node]
}
