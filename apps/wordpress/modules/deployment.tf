resource "kubernetes_deployment" "wordpress" {

  metadata {
    name      = "wordpress"
    namespace = kubernetes_namespace.wordpress.metadata[0].name

    labels = {
      app = "wordpress"
    }
  }

  spec {

    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "wordpress"
      }
    }

    template {

      metadata {

        labels = {
          app = "wordpress"
        }

      }

      spec {

        service_account_name = kubernetes_service_account.wordpress.metadata[0].name

        security_context {

          fs_group = 33

        }

        affinity {

          pod_anti_affinity {

            preferred_during_scheduling_ignored_during_execution {

              weight = 100

              pod_affinity_term {

                topology_key = "kubernetes.io/hostname"

                label_selector {

                  match_labels = {
                    app = "wordpress"
                  }

                }

              }

            }

          }

        }

        container {

          name  = "wordpress"
          image = "wordpress:php8.3-apache"

          image_pull_policy = "IfNotPresent"

          port {

            container_port = 80

          }

          env {

            name  = "WORDPRESS_DB_HOST"
            value = var.db_host

          }

          env {

            name  = "WORDPRESS_DB_NAME"
            value = var.db_name

          }

          env {

            name  = "WORDPRESS_DB_USER"
            value = var.db_user

          }

          env {

            name = "WORDPRESS_DB_PASSWORD"

            value_from {

              secret_key_ref {

                ####name = kubernetes_secret.wordpress_db.metadata[0].name #####Humne secret.tf delete kar diya, lekin deployment.tf abhi bhi purane kubernetes_secret.wordpress_db resource ko reference kar raha hai
                name = "wordpress-db" ##"wordpress-db" wahi Secret hai jo External Secrets create karega.
                key  = "password"

              }

            }

          }

          volume_mount {

            name       = "wordpress-data"
            mount_path = "/var/www/html"

          }

          resources {

            requests = {

              cpu    = "100m"
              memory = "128Mi"

            }

            limits = {

              cpu    = "250m"
              memory = "500Mi"

            }

          }

          liveness_probe {

            http_get {

              path = "/"
              port = 80

            }

            initial_delay_seconds = 120
            timeout_seconds       = 5
            period_seconds        = 20

          }

          readiness_probe {

            http_get {

              path = "/"
              port = 80

            }

            initial_delay_seconds = 30
            timeout_seconds       = 5
            period_seconds        = 10

          }

          startup_probe {

            http_get {

              path = "/"
              port = 80

            }

            timeout_seconds   = 10
            failure_threshold = 30
            period_seconds    = 10

          }

        }

        volume {

          name = "wordpress-data"

          persistent_volume_claim {

            claim_name = kubernetes_persistent_volume_claim.wordpress.metadata[0].name

          }

        }

      }

    }

  }

  depends_on = [

    ##kubernetes_secret.wordpress_db, ###We are using external secret
    kubernetes_persistent_volume_claim.wordpress,
    kubernetes_service_account.wordpress
  ]

}
