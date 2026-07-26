resource "google_service_account" "jenkins_vm_sa" {
  account_id   = "jenkins-vm-sa"
  display_name = "Jenkins VM Service Account"
  project      = var.project_id
}

# Docker images Artifact Registry me push karne ke liye
resource "google_project_iam_member" "jenkins_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.jenkins_vm_sa.email}"
}

# GKE cluster me deploy karne ke liye (kubectl apply chalane ki permission)
resource "google_project_iam_member" "jenkins_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.jenkins_vm_sa.email}"
}

# GKE cluster credentials fetch karne ke liye
resource "google_project_iam_member" "jenkins_gke_viewer" {
  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "serviceAccount:${google_service_account.jenkins_vm_sa.email}"
}

resource "google_compute_firewall" "jenkins_allow_http" {
  name    = "allow-jenkins-ui"
  network = var.vpc_id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  # Practice ke liye sabse allow — production me apna IP/VPN CIDR rakhna
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jenkins-server"]
}

resource "google_compute_firewall" "jenkins_allow_ssh" {
  name    = "allow-jenkins-ssh"
  network = var.vpc_id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jenkins-server"]
}

resource "google_compute_instance" "jenkins" {
  name         = "jenkins-server"
  machine_type = var.machine_type
  zone         = "${var.region}-a"
  project      = var.project_id
  tags         = ["jenkins-server"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = var.vpc_id
    subnetwork = var.subnet_id
    access_config {} # public IP milega
  }

  service_account {
    email  = google_service_account.jenkins_vm_sa.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = file("${path.module}/startup.sh")
}

