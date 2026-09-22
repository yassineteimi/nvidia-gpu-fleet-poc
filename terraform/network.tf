########################################
# SSH key
########################################

resource "scaleway_iam_ssh_key" "admin" {
  name       = "${var.cluster_name}-admin"
  public_key = local.ssh_public_key

  lifecycle {
    precondition {
      condition     = local.ssh_public_key != ""
      error_message = "No SSH public key. Run scripts/cluster-up.sh, which derives it from SSH_PRIVATE_KEY_PATH in .env, or point ssh_public_key_path at a readable .pub file."
    }
  }
}

########################################
# Private network
########################################

resource "scaleway_vpc" "main" {
  name = var.cluster_name
  tags = local.tags
}

resource "scaleway_vpc_private_network" "main" {
  name   = "${var.cluster_name}-pn"
  vpc_id = scaleway_vpc.main.id
  tags   = local.tags

  ipv4_subnet {
    subnet = var.private_network_subnet
  }
}

# Both node addresses are booked in IPAM up front. The control plane address in
# particular has to be known before the node boots, because it goes into the API
# server advertise address, the certificate SANs and the join endpoint that the
# GPU node uses days later. Scaleway warns that a specific address must be booked
# before anything else claims it, hence the depends_on relations on the NICs.

resource "scaleway_ipam_ip" "control_plane" {
  address = var.control_plane_private_ip
  tags    = local.tags

  source {
    private_network_id = scaleway_vpc_private_network.main.id
  }
}

resource "scaleway_ipam_ip" "gpu_node" {
  count = var.gpu_node_enabled ? 1 : 0

  address = var.gpu_node_private_ip
  tags    = local.tags

  source {
    private_network_id = scaleway_vpc_private_network.main.id
  }
}

########################################
# Security groups
########################################

# Scaleway security groups filter the public interface only. Traffic between the
# two nodes over the Private Network is not filtered here, which is why there is
# no rule for the kubelet port, etcd, VXLAN or NodePorts while node_ip_mode is
# private: none of that ever touches a public interface.
#
# In public mode the two nodes talk to each other over their flexible IPs, so
# each security group opens up to the other node's address and nothing else.

resource "scaleway_instance_security_group" "control_plane" {
  name                    = "${var.cluster_name}-cp"
  description             = "Control plane: SSH and the Kubernetes API from admin ranges"
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  tags                    = local.tags

  dynamic "inbound_rule" {
    for_each = var.admin_cidrs
    content {
      action   = "accept"
      protocol = "TCP"
      port     = 22
      ip_range = inbound_rule.value
    }
  }

  dynamic "inbound_rule" {
    for_each = var.admin_cidrs
    content {
      action   = "accept"
      protocol = "TCP"
      port     = 6443
      ip_range = inbound_rule.value
    }
  }

  dynamic "inbound_rule" {
    for_each = local.public_mode && var.gpu_node_enabled ? [scaleway_instance_ip.gpu_node[0].address] : []
    content {
      action   = "accept"
      protocol = "ANY"
      ip_range = "${inbound_rule.value}/32"
    }
  }
}

resource "scaleway_instance_security_group" "gpu_node" {
  name                    = "${var.cluster_name}-gpu"
  description             = "GPU node: SSH from admin ranges"
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  tags                    = local.tags

  dynamic "inbound_rule" {
    for_each = var.admin_cidrs
    content {
      action   = "accept"
      protocol = "TCP"
      port     = 22
      ip_range = inbound_rule.value
    }
  }

  dynamic "inbound_rule" {
    for_each = local.public_mode ? [scaleway_instance_ip.control_plane.address] : []
    content {
      action   = "accept"
      protocol = "ANY"
      ip_range = "${inbound_rule.value}/32"
    }
  }
}
