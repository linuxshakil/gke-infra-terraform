#########################################################
# Jenkins Google Service Account
#########################################################

resource "google_service_account" "jenkins" {

  account_id = "jenkins-gke-sa"

  display_name = "Jenkins Service Account for GKE"

}
