########################################
# Placement
########################################

variable "region" {
  description = "Scaleway region. Private Networks are regional resources."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = <<-EOT
    Scaleway zone for both instances. fr-par-2 is the primary choice because it
    carries L4 stock. pl-waw-2 is the documented fallback when fr-par-2 is out of
    L4 capacity. Changing this also requires changing the region.
  EOT
  type        = string
  default     = "fr-par-2"
}

variable "cluster_name" {
  description = "Prefix applied to every resource name and used as the Kubernetes cluster name."
  type        = string
  default     = "gpu-fleet"
}

########################################
# Access
########################################

variable "ssh_public_key" {
  description = <<-EOT
    Public SSH key material to register on both nodes. The scripts derive this
    from SSH_PRIVATE_KEY_PATH in .env and export it as TF_VAR_ssh_public_key, so
    the key on the nodes is by construction the key you log in with. Leave it
    empty and ssh_public_key_path is read instead, which is what happens when
    Terraform is run directly rather than through scripts/.
  EOT
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = <<-EOT
    Fallback path to a public SSH key file, used only when ssh_public_key is
    empty. Prefer letting the scripts supply the key: a path here and a
    different path in .env is a mismatch nothing catches until the SSH wait
    loop times out.
  EOT
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidrs" {
  description = <<-EOT
    Source ranges allowed to reach SSH and the Kubernetes API on the public
    interface. The default is open because a laptop on a residential connection
    has no stable address. Narrow it if yours is stable. SSH is key only and the
    API is client certificate only, so this is not the only control, but it is
    the cheapest one.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

########################################
# Private network addressing
########################################

variable "private_network_subnet" {
  description = "IPv4 CIDR of the Private Network the two nodes share."
  type        = string
  default     = "172.16.32.0/22"
}

variable "control_plane_private_ip" {
  description = <<-EOT
    Private IPv4 reserved in IPAM for the control plane. Reserving it rather than
    taking whatever DHCP hands out means the API server advertise address, the
    certificate SANs and the join endpoint are all known before the node boots.
    Must fall inside private_network_subnet.
  EOT
  type        = string
  default     = "172.16.32.10"
}

variable "gpu_node_private_ip" {
  description = "Private IPv4 reserved in IPAM for the GPU node. Must fall inside private_network_subnet."
  type        = string
  default     = "172.16.32.20"
}

variable "node_ip_mode" {
  description = <<-EOT
    Which address the kubelet advertises and which endpoint nodes join through.
    "private" keeps all cluster traffic on the Scaleway Private Network.
    "public" switches both nodes to their flexible public IPs, which is the
    escape hatch if Private Network DHCP or IPAM misbehaves. Switching is a one
    value change followed by a rebuild of both nodes.
  EOT
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public"], var.node_ip_mode)
    error_message = "node_ip_mode must be either private or public."
  }
}

########################################
# Control plane node
########################################

variable "control_plane_type" {
  description = <<-EOT
    Commercial type of the persistent control plane node. PLAY2-MICRO is 4 vCPU
    and 8 GB, which holds etcd, the control plane, ArgoCD and kube-prometheus-stack.
    Verify the SKU is offered in your zone before the first apply:
    scw instance server-type list zone=fr-par-2
  EOT
  type        = string
  default     = "PLAY2-MICRO"
}

variable "control_plane_root_volume_size_gb" {
  description = "Root volume size for the control plane. Prometheus retention lives here."
  type        = number
  default     = 80
}

variable "control_plane_image" {
  description = "Scaleway image label for the control plane node."
  type        = string
  default     = "ubuntu_jammy"
}

########################################
# GPU node
########################################

variable "gpu_node_enabled" {
  description = <<-EOT
    Whether the GPU node should exist. It defaults to false so that a bare
    terraform apply never leaves a GPU billing by accident. scripts/gpu-up.sh
    flips it to true and scripts/gpu-down.sh flips it back, both by writing
    gpu.auto.tfvars, so the desired state is always a declared fact rather than
    a -target flag applied once and forgotten.
  EOT
  type        = bool
  default     = false
}

variable "gpu_node_type" {
  description = "Commercial type of the GPU node. L4-1-24G is one NVIDIA L4 with 24 GB."
  type        = string
  default     = "L4-1-24G"
}

variable "gpu_node_root_volume_size_gb" {
  description = <<-EOT
    Root volume size for the GPU node. The driver image, the container toolkit,
    a CUDA base image and a PyTorch image together are tens of gigabytes, so this
    is deliberately larger than the control plane.
  EOT
  type        = number
  default     = 150
}

variable "gpu_node_image" {
  description = <<-EOT
    Scaleway image label for the GPU node. This must be a plain Ubuntu image.
    Scaleway also publishes GPU OS images with the NVIDIA driver and container
    toolkit preinstalled. Using one of those would take the driver lifecycle away
    from the GPU Operator, which is the single thing this PoC exists to
    demonstrate, so the validation below refuses them.
  EOT
  type        = string
  default     = "ubuntu_jammy"

  validation {
    condition     = !can(regex("gpu_os", var.gpu_node_image))
    error_message = "The GPU node must boot a plain Ubuntu image. A gpu_os image ships preinstalled NVIDIA drivers and would bypass the GPU Operator."
  }
}

variable "root_volume_type" {
  description = "Root volume type for both nodes. sbs_volume is Scaleway Block Storage, which both PLAY2 and L4 instances use."
  type        = string
  default     = "sbs_volume"
}

########################################
# Kubernetes
########################################

variable "kubernetes_minor" {
  description = <<-EOT
    Kubernetes minor version. This selects the pkgs.k8s.io apt repository, so it
    is the version the whole cluster is pinned to.
  EOT
  type        = string
  default     = "1.36"
}

variable "kubernetes_package_version" {
  description = <<-EOT
    Exact Debian package version for kubelet, kubeadm and kubectl, for example
    1.36.4-1.1. Leave empty to take the newest patch in kubernetes_minor. After
    the first apply, read the installed version off a node and set it here so the
    cluster rebuilds bit for bit:

      ssh root@<control plane> 'dpkg-query -W -f=$${Version} kubeadm'
  EOT
  type        = string
  default     = ""
}

variable "pod_subnet" {
  description = "Pod CIDR. 10.244.0.0/16 is what the stock Flannel manifest expects."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_subnet" {
  description = "Service CIDR."
  type        = string
  default     = "10.96.0.0/12"
}

variable "flannel_version" {
  description = "Flannel release tag. The manifest is fetched from the GitHub release asset for this tag."
  type        = string
  default     = "v0.28.9"
}
