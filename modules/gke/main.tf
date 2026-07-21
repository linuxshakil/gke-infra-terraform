resource "google_container_cluster" "primary" {
  name       = var.cluster_name
  location   = var.region
  network    = var.vpc_id
  subnetwork = var.subnet_id

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods-range"
    services_secondary_range_name = "services-range"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "allowed-all-temp"
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }

    http_load_balancing {
      disabled = false
    }
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS"
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS"
    ]
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "18:00"
    }
  }

  deletion_protection = false

  lifecycle {
    ignore_changes = [
      node_config
    ]
  }
}

resource "google_service_account" "gke_node_sa" {
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node Service Account"
}

resource "google_project_iam_member" "gke_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_container_node_pool" "primary_nodes" {
  name     = "${var.cluster_name}-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = 20
    disk_type       = "pd-standard"
    service_account = var.node_service_account
    ##service_account = google_service_account.gke_node_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      env = "production"
    }

    tags = [
      "gke-node",
      "${var.cluster_name}-node"
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
