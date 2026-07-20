output "hpa_name" {
  value = kubernetes_horizontal_pod_autoscaler_v2.wordpress.metadata[0].name
}
