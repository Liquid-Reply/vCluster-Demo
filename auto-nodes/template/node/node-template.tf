locals {
  project            = module.validation.project
  region             = module.validation.region
  zone               = module.validation.zone
  vcluster_name      = nonsensitive(var.vcluster.instance.metadata.name)
  vcluster_namespace = nonsensitive(var.vcluster.instance.metadata.namespace)

  network_name          = nonsensitive(var.vcluster.nodeEnvironment.outputs.infrastructure["network_name"])
  subnet_name           = nonsensitive(var.vcluster.nodeEnvironment.outputs.infrastructure["subnet_name"])
  service_account_email = nonsensitive(var.vcluster.nodeEnvironment.outputs.infrastructure["service_account_email"])

  instance_type = nonsensitive(var.vcluster.nodeType.spec.properties["instance-type"])

  # GPU properties
  accelerator       = try(nonsensitive(var.vcluster.nodeType.spec.properties["accelerator"]), "none")
  accelerator_count = try(tonumber(nonsensitive(var.vcluster.nodeType.spec.properties["accelerator-count"])), 0)
  has_gpu           = local.accelerator != "none" && local.accelerator != "" && local.accelerator_count > 0

  # Startup scripts
  gpu_startup_script = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/gpu-setup.log 2>&1

    echo "=== GPU Setup Started ==="

    # Wait for cloud-init and apt
    cloud-init status --wait || true
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 1; done

    # Install NVIDIA driver
    echo "Installing NVIDIA driver..."
    apt-get update
    apt-get install -y linux-headers-$(uname -r)
    apt-get install -y nvidia-driver-535

    # Install NVIDIA Container Toolkit
    echo "Installing NVIDIA Container Toolkit..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update
    apt-get install -y nvidia-container-toolkit

    # Configure containerd for NVIDIA
    echo "Configuring containerd..."
    nvidia-ctk runtime configure --runtime=containerd
    systemctl restart containerd

    echo "=== GPU Setup Complete ==="
  EOF

  cpu_startup_script = <<-EOF
    #!/bin/bash
    cloud-init status --wait || true
  EOF

  startup_script = local.has_gpu ? local.gpu_startup_script : local.cpu_startup_script
}

provider "google" {
  project = local.project
  region  = local.region
}

module "validation" {
  source  = "../validation"
  project = nonsensitive(var.vcluster.properties["project"])
  region  = nonsensitive(var.vcluster.properties["region"])
  zone    = try(nonsensitive(var.vcluster.properties["zone"]), "")
}

resource "random_id" "vm_suffix" {
  byte_length = 4
}

data "google_project" "project" {
  project_id = local.project
}

data "google_compute_image" "img" {
  family  = "ubuntu-2404-lts-amd64"
  project = "ubuntu-os-cloud"
}

module "instance_template" {
  source  = "terraform-google-modules/vm/google//modules/instance_template"
  version = "~> 13.6.0"

  region             = local.region
  project_id         = local.project
  network            = local.network_name
  subnetwork         = local.subnet_name
  subnetwork_project = local.project

  tags = ["allow-iap-ssh", local.vcluster_name]

  machine_type = local.instance_type

  source_image         = data.google_compute_image.img.self_link
  source_image_family  = data.google_compute_image.img.family
  source_image_project = data.google_compute_image.img.project

  disk_size_gb = 100
  disk_type    = "pd-balanced"

  service_account = {
    email  = local.service_account_email
    scopes = ["cloud-platform"]
  }

  # GPU Configuration
  gpu = local.has_gpu ? {
    type  = local.accelerator
    count = local.accelerator_count
  } : null

  # Required for GPU instances
  on_host_maintenance = local.has_gpu ? "TERMINATE" : "MIGRATE"

  metadata = {
    user-data = var.vcluster.userData != "" ? var.vcluster.userData : null
  }

  startup_script = local.startup_script
}

module "private_instance" {
  source  = "terraform-google-modules/vm/google//modules/compute_instance"
  version = "~> 13.6.0"

  region            = local.region
  zone              = local.zone == "" ? null : local.zone
  subnetwork        = local.subnet_name
  num_instances     = 1
  hostname          = "${var.vcluster.name}-${random_id.vm_suffix.hex}"
  instance_template = module.instance_template.self_link

  access_config = []

  labels = {
    vcluster     = local.vcluster_name
    namespace    = local.vcluster_namespace
    cluster-name = local.vcluster_name
    gpu          = local.has_gpu ? "true" : "false"
  }
}