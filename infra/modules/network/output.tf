output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "subnet_id" {
  value = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  value = google_compute_subnetwork.subnet.name
}

output "subnet_self_link" {
  value = google_compute_subnetwork.subnet.self_link
}

output "private_service_connection" {
  value = google_service_networking_connection.private_vpc_connection.peering
}

output "private_service_range_name" {
  value = google_compute_global_address.private_service_range.name
}
