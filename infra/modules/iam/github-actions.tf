resource "google_service_account" "github_actions" {

  account_id = "github-actions-sa"

  display_name = "GitHub Actions WIF SA"

}
