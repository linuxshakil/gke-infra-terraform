############################################################
# GitHub Actions Required IAM Roles
############################################################

locals {

  github_roles = [

    "roles/container.admin",

    "roles/compute.networkAdmin",

    "roles/iam.serviceAccountAdmin",

    "roles/iam.serviceAccountUser",

    "roles/iam.workloadIdentityPoolAdmin",

    "roles/resourcemanager.projectIamAdmin",

    "roles/storage.admin",

    "roles/secretmanager.admin",

    "roles/cloudsql.admin",

    "roles/artifactregistry.admin",

    "roles/serviceusage.serviceUsageAdmin"

  ]

}

resource "google_project_iam_member" "github_roles" {

  for_each = toset(local.github_roles)

  project = var.project_id

  role = each.value

  member = "serviceAccount:${google_service_account.github_actions.email}"

}
