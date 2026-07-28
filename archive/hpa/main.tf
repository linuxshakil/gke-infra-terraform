resource "kubernetes_horizontal_pod_autoscaler_v2" "wordpress" {

  metadata {
    name      = "wordpress-hpa"
    namespace = var.namespace
  }

  spec {

    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = var.deployment_name
    }

    metric {

      type = "Resource"

      resource {

        name = "cpu"

        target {

          type                = "Utilization"
          average_utilization = var.cpu_utilization

        }
      }
    }

    behavior {

      scale_up {

        stabilization_window_seconds = 0

        policy {

          type           = "Percent"
          value          = 100
          period_seconds = 60
        }

        select_policy = "Max"
      }

      scale_down {

        stabilization_window_seconds = 300

        policy {

          type           = "Percent"
          value          = 50
          period_seconds = 60
        }

        select_policy = "Max"
      }
    }
  }
}
