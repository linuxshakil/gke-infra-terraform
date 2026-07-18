resource "google_compute_global_address" "private_service_range" {
  name         = "google-managed-services-${var.cluster_name}"
  purpose      = "VPC_PEERING"
  address_type = "INTERNAL"

  network       = google_compute_network.vpc.id
  address       = var.private_service_range
  prefix_length = var.private_service_prefix
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network = google_compute_network.vpc.id
  service = "servicenetworking.googleapis.com"

  reserved_peering_ranges = [
    google_compute_global_address.private_service_range.name
  ]

  depends_on = [
    google_project_service.service_networking,
    google_compute_global_address.private_service_range
  ]
}
