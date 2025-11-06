terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Define the list of APIs to enable
locals {
  gke_apis = [
    "container.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "storage.googleapis.com"
  ]
}

# 1. Enable all the necessary APIs
resource "google_project_service" "gke_apis" {
  for_each                   = toset(local.gke_apis)
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = true
  disable_on_destroy         = false
}

# 2. Create the custom VPC
resource "google_compute_network" "gke_vpc" {
  project                 = var.project_id
  name                    = "gke-vpc"
  auto_create_subnetworks = false # This is --subnet-mode=custom
  description             = "Custom VPC for GKE cluster and bastion host"
}

# 3. Create the GKE subnet with secondary ranges
resource "google_compute_subnetwork" "gke_subnet" {
  project       = var.project_id
  name          = "gke-subnet"
  region        = var.region
  network       = google_compute_network.gke_vpc.id
  ip_cidr_range = "192.168.0.0/24"

  secondary_ip_range {
    range_name    = "pod"
    ip_cidr_range = "10.10.0.0/18"
  }
  secondary_ip_range {
    range_name    = "svc"
    ip_cidr_range = "10.10.64.0/18"
  }

  # This resource must wait for the APIs to be enabled
  depends_on = [
    google_project_service.gke_apis
  ]
}

# 4. Reserve the static IP for Cloud NAT
resource "google_compute_address" "gke_nat_ip" {
  project = var.project_id
  name    = "gke-nat-ip"
  region  = var.region
}

# 5. Create the Cloud Router
resource "google_compute_router" "gke_router" {
  project = var.project_id
  name    = "gke-router"
  region  = var.region
  network = google_compute_network.gke_vpc.id
}

# 6. Create the NAT Gateway
resource "google_compute_router_nat" "gke_nat_gateway" {
  project = var.project_id
  name    = "gke-nat-gateway"
  router  = google_compute_router.gke_router.name
  region  = var.region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = [google_compute_address.gke_nat_ip.self_link]

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.gke_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# 7. Create the IAP SSH Firewall Rule
resource "google_compute_firewall" "allow_iap_ssh" {
  project = var.project_id
  name    = "allow-iap-ssh"
  network = google_compute_network.gke_vpc.name

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"] # Google's IAP range
  target_tags   = ["ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Create a service account for the bastion host
resource "google_service_account" "bastion_sa" {
  project      = var.project_id
  account_id   = "bastion-sa"
  display_name = "Service Account for Bastion Host (GKE Access)"
}

# Attach IAM roles to the bastion service account
resource "google_project_iam_member" "bastion_sa_roles" {
  for_each = toset([
    "roles/container.admin",        # Full control over GKE clusters and workloads
    "roles/iam.serviceAccountUser", # To use service accounts with GCP services
    "roles/viewer",                 # To view project resources
    "roles/storage.admin"           # Optional: to push/pull container images or configs
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.bastion_sa.email}"
}


# 8. Create the Bastion VM
resource "google_compute_instance" "bastion_host" {
  project      = var.project_id
  name         = "bastion-host"
  machine_type = "e2-standard-2"
  zone         = "${var.region}-a" # Automatically matches your region
  tags         = ["ssh"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size = 30
    }
  }

  network_interface {
    network    = google_compute_network.gke_vpc.id
    subnetwork = google_compute_subnetwork.gke_subnet.id
    # No "access_config" => no external IP (IAP-only SSH)
  }

  service_account {
    email  = google_service_account.bastion_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "[INFO] Updating package lists..."
    apt-get update -y

    echo "[INFO] Installing required dependencies..."
    apt-get install -y apt-transport-https ca-certificates gnupg curl

    echo "[INFO] Adding Google Cloud SDK repo and GPG key..."
    mkdir -p /usr/share/keyrings
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      | tee /etc/apt/sources.list.d/google-cloud-sdk.list

    echo "[INFO] Installing gcloud CLI..."
    apt-get update -y && apt-get install -y google-cloud-cli

    echo "[INFO] Installing kubectl..."
    apt-get install -y kubectl

    echo "[INFO] Installing GKE Auth Plugin..."
    apt-get install -y google-cloud-sdk-gke-gcloud-auth-plugin

    echo "[INFO] Configuring system-wide access..."
    ln -sf /usr/bin/kubectl /usr/local/bin/kubectl
    ln -sf /usr/bin/gcloud /usr/local/bin/gcloud

    echo "[INFO] Installation complete."
  EOT

  

  # This VM needs internet for the startup script,
  # so ensure NAT gateway is active first
  depends_on = [
    google_compute_router_nat.gke_nat_gateway, google_project_iam_member.bastion_sa_roles
  ]
}

# resource "google_project_iam_member" "container_admins" {
#   for_each = toset(var.container_admin_users)

#   project = var.project_id
#   role    = "roles/container.admin"
#   member  = "user:${each.key}"
# }

