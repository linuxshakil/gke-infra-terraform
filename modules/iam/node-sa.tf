#########################################################
# Existing GKE Node Service Account
#########################################################

data "google_service_account" "node_sa" {

  account_id = "prod-gke-cluster-node-sa"

}
