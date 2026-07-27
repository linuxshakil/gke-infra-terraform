# GKE Production Infrastructure on GCP — Terraform Project

A production-style, end-to-end **Infrastructure as Code (IaC)** project that provisions a private GKE cluster on Google Cloud along with networking, IAM, Cloud SQL, Secret Manager, Artifact Registry, automated backups, and a full GitHub Actions CI/CD pipeline using **Workload Identity Federation (no service account keys)**.

This README is written so that anyone — including someone learning Terraform for the first time — can clone this repo, understand every module, run it end-to-end, and also use it as interview/revision material.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture](#2-architecture)
3. [Repository Structure](#3-repository-structure)
4. [Technologies Used](#4-technologies-used)
5. [Prerequisites](#5-prerequisites)
6. [Install Everything](#6-install-everything)
7. [Bootstrap](#7-bootstrap)
8. [Infrastructure](#8-infrastructure)
9. [Module by Module Explanation](#9-module-by-module-explanation)
10. [GitHub Actions](#10-github-actions)
11. [Workload Identity Federation](#11-workload-identity-federation-wif)
12. [Terraform Backend](#12-terraform-backend)
13. [State File](#13-state-file)
14. [Deployment Walkthrough](#14-deployment-walkthrough)
15. [Verification Commands](#15-verification-commands)
16. [Destroy Walkthrough](#16-destroy-walkthrough)
17. [Cost Estimation](#17-cost-estimation)
18. [Security Best Practices](#18-security-best-practices)
19. [Troubleshooting](#19-troubleshooting)
20. [FAQ](#20-faq)
21. [Interview Questions](#21-interview-questions)
22. [Learning Notes](#22-learning-notes)
23. [Future Improvements](#23-future-improvements)

---

## 1. Introduction

This repository demonstrates how a **real production Kubernetes platform** is built on Google Cloud using **100% Terraform**, instead of clicking around the GCP Console.

The reference workload deployed on top of the platform is **WordPress** (a common, relatable example), backed by:

- A **private GKE cluster** (nodes have no public IP)
- A **private Cloud SQL (MySQL)** database reachable only inside the VPC
- **Secret Manager** for storing DB credentials (never in plain text/Git)
- **External Secrets Operator** to sync GCP secrets into Kubernetes Secrets
- **Artifact Registry** to store custom Docker images (e.g., the backup job image)
- A **Kubernetes CronJob** that backs up the database + WordPress uploads to Cloud Storage every day
- **GitHub Actions** that deploys all of this automatically, authenticating to GCP via **OIDC / Workload Identity Federation** — no static JSON keys stored anywhere

The project is split into two independent Terraform "root modules":

| Root Module | Purpose | Runs |
|---|---|---|
| `bootstrap/` | One-time setup: state bucket + CI/CD identity | Manually, once |
| `infra/` | The actual platform (VPC, GKE, SQL, etc.) | Every push via GitHub Actions |

This separation is a **real-world pattern**: you can't create the Terraform state bucket *using* Terraform state that lives in that same bucket (chicken-and-egg problem), so bootstrap is always a separate, smaller, one-time Terraform project.

---

## 2. Architecture

### High Level Architecture

```
                         ┌───────────────────────┐
                         │   GitHub Repository    │
                         └───────────┬───────────┘
                                     │ push / workflow_dispatch
                                     ▼
                         ┌───────────────────────┐
                         │  GitHub Actions (CI)   │
                         │  OIDC Token Generated  │
                         └───────────┬───────────┘
                                     │ exchanged via
                                     ▼
                 ┌───────────────────────────────────────┐
                 │   Workload Identity Federation (WIF)   │
                 │   github-actions-sa@<project>.iam      │
                 └───────────────────┬────────────────────┘
                                     │ short-lived token
                                     ▼
                         ┌───────────────────────┐
                         │        Terraform       │
                         │  (state in GCS bucket) │
                         └───────────┬───────────┘
                                     │ creates
        ┌────────────────────────────┼─────────────────────────────┐
        ▼                            ▼                             ▼
┌───────────────┐          ┌──────────────────┐          ┌───────────────────┐
│  VPC Network  │          │  Artifact Registry│          │        IAM         │
│  + Subnet     │          │  (Docker images)  │          │  (Service Accounts)│
│  + Cloud NAT  │          └──────────────────┘          └───────────────────┘
└───────┬───────┘
        │ private
        ▼
┌────────────────────┐        ┌───────────────────────┐
│   GKE (Private)     │◄──────►│   Cloud SQL (MySQL)   │
│   Node Pool         │  VPC   │   Private IP only     │
│   Workload Identity │  peer  └───────────┬───────────┘
└─────────┬──────────┘                     │
          │                                 ▼
          │                     ┌───────────────────────┐
          ▼                     │    Secret Manager      │
┌────────────────────┐          │  (wordpress-db-password)│
│    WordPress Pod    │          └───────────┬───────────┘
│  (Deployment + PVC) │                      │ synced by
│  + Service/Ingress  │◄─────────────────────┘
└─────────┬──────────┘   External Secrets Operator
          │
          ▼
┌────────────────────┐
│   Backup CronJob    │───► Cloud Storage bucket (SQL dump + uploads archive)
└────────────────────┘
```

### Resource Flow

Terraform builds resources in this dependency order (see `infra/main.tf`):

1. **`network`** module → VPC, subnet, secondary ranges, Cloud Router, Cloud NAT, private-services peering
2. **`iam`** module → all service accounts (node, WordPress, external-secrets, GitHub Actions, Jenkins legacy, backup) + their IAM bindings
3. **`gke`** module → private GKE cluster + node pool (depends on `network` + `iam` for the node service account)
4. **`cloudsql`** module → private MySQL instance, database, user, random password (depends on `network` for the VPC peering)
5. **`secret-manager`** module → stores the Cloud SQL password generated above (depends on `cloudsql`)
6. **`artifact-registry`** module → Docker repository for the backup job image (independent)
7. **`backup`** module → GCS bucket + backup service account + Workload Identity binding (depends on `cloudsql` for its service account)

### CI/CD Flow

```
Developer pushes code
        │
        ▼
GitHub Actions triggered (infra.yml)
        │
        ▼
OIDC token requested (permissions: id-token: write)
        │
        ▼
google-github-actions/auth exchanges OIDC token
for short-lived GCP access token (via WIF Provider)
        │
        ▼
terraform init  → connects to GCS backend
terraform fmt   → style check
terraform validate → syntax/logic check
terraform plan  → saved as an artifact (tfplan)
        │
        ├── on Pull Request → stop after plan (review only)
        │
        └── on push to main → terraform apply -auto-approve tfplan
                    │
                    ▼
        Outputs exported as JSON + uploaded as workflow artifacts
                    │
                    ▼
        Job Summary posted on the GitHub Actions run page
```

---

## 3. Repository Structure

```
gke-infra-terraform/
├── bootstrap/                  # One-time setup (state bucket + WIF + CI SA)
│   ├── main.tf
│   ├── iam.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── versions.tf
│   └── terraform.tfvars
│
├── infra/                      # The actual platform — deployed continuously
│   ├── main.tf                 # Wires all modules together
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf            # google, google-beta, kubernetes, helm
│   ├── versions.tf
│   ├── backend.tf              # Remote state config (GCS)
│   ├── terraform.tfvars
│   └── modules/
│       ├── network/            # VPC, subnet, NAT, private services peering
│       ├── iam/                # All service accounts + IAM bindings
│       ├── gke/                 # Private GKE cluster + node pool
│       ├── cloudsql/            # Private MySQL instance
│       ├── secret-manager/      # Stores DB password as a GCP secret
│       ├── artifact-registry/   # Docker repo for backup images
│       └── backup/              # Backup bucket + backup service account
│
├── modules/                    # Reusable app-layer modules (Kubernetes objects)
│   └── hpa/                     # HorizontalPodAutoscaler for WordPress
│
├── apps/modules/                # Kubernetes workload definitions
│   ├── wordpress/               # Deployment, Service, Ingress, PVC, BackendConfig
│   └── external-secrets/        # External Secrets Operator wiring
│
├── backup-job/                  # Docker image + scripts for the backup CronJob
│   ├── Dockerfile
│   ├── backup.sh / restore.sh / entrypoint.sh
│   └── cronjob.yaml / restore-job.yaml
│
├── archive/                     # Old/legacy experiments (Jenkins VM, raw k8s yaml)
│                                 # Kept for history — not part of the active pipeline
│
└── .github/workflows/
    ├── bootstrap.yml             # Runs the bootstrap/ root module manually
    ├── infra.yml                 # Runs the infra/ root module on every push
    └── terraform-infra-destroy.yml  # Manually destroys infra/ (with a confirm gate)
```

> **Note:** `archive/` contains earlier iterations of this project (a Jenkins-based CI/CD and raw Kubernetes YAML before it was converted into Terraform + External Secrets). It's kept only to show the evolution of the project — it is not deployed.

---

## 4. Technologies Used

| Category | Tool |
|---|---|
| IaC | Terraform ≥ 1.15 |
| Cloud Provider | Google Cloud Platform (GCP) |
| Container Orchestration | Google Kubernetes Engine (GKE), private cluster |
| Database | Cloud SQL for MySQL 8.0 (private IP) |
| Secrets | Google Secret Manager + External Secrets Operator |
| Container Registry | Artifact Registry |
| CI/CD | GitHub Actions |
| Auth (CI → Cloud) | Workload Identity Federation (OIDC, keyless) |
| App Workload | WordPress (Deployment, PVC, Service, Ingress) |
| Autoscaling | Kubernetes HPA (`autoscaling/v2`) |
| Backup | Custom Docker image + Kubernetes CronJob + Cloud Storage |
| Terraform Providers | `google`, `google-beta`, `kubernetes`, `helm`, `kubectl`, `random`, `archive` |

---

## 5. Prerequisites

Before you start, make sure you have:

- A **Google Cloud Project** with billing enabled
- **Owner** or equivalent broad IAM role on that project (only for the very first bootstrap run — after that, the GitHub Actions service account takes over)
- A **GitHub repository** (this one, forked/cloned) to push code to and run Actions from
- Ability to enable GCP APIs on the project (`serviceusage.googleapis.com`)
- Basic familiarity with the command line

You do **not** need a Kubernetes cluster already running — Terraform creates it.

---

## 6. Install Everything

### Terraform

```bash
# Linux
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform -version   # should be >= 1.15.0
```

### gcloud (Google Cloud SDK)

```bash
# Linux
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# macOS
brew install --cask google-cloud-sdk

# Initialize & login
gcloud init
gcloud auth login
gcloud auth application-default login   # needed for local Terraform runs
```

### kubectl

```bash
gcloud components install kubectl
# OR
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

### Git

```bash
sudo apt install git      # Linux
brew install git          # macOS
git --version
```

---

## 7. Bootstrap

### Why Bootstrap?

Terraform needs somewhere to store its **state file** remotely (so it's shared, locked, and versioned), and GitHub Actions needs an **identity** to authenticate to GCP. But we don't want to:

- Store a GCP service account **JSON key** in GitHub Secrets (long-lived credentials = security risk)
- Create the state bucket using state that would need to live in... the bucket that doesn't exist yet

So `bootstrap/` is a small, separate Terraform project that is run **once, manually, with your own personal GCP credentials**, and its only job is to create the things needed so that the *real* infra pipeline can run securely and automatically afterward.

### Resources Created

From `bootstrap/main.tf` and `bootstrap/iam.tf`:

- Enables required APIs: `iam`, `iamcredentials`, `cloudresourcemanager`, `sts`, `storage`
- **GCS bucket** for Terraform remote state (versioned, with a lifecycle rule keeping only the last 5 versions)
- **GitHub Actions service account** (`github-actions-sa`)
- **Workload Identity Pool** (`github-actions-pool-v1`)
- **Workload Identity Pool Provider** bound to `token.actions.githubusercontent.com`, restricted with `attribute_condition = "assertion.repository == \"<owner>/<repo>\""` so **only your repo** can impersonate this identity
- IAM binding allowing that identity pool to impersonate the GitHub Actions service account
- A set of **project IAM roles** granted to the GitHub Actions SA (Container Admin, Network Admin, Service Account Admin/User, Storage Admin, Secret Manager Admin, Cloud SQL Admin, Artifact Registry Admin, etc.) — everything the `infra/` pipeline needs to create resources

### Execution

```bash
cd bootstrap
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

Or trigger the **`bootstrap.yml`** workflow manually from the GitHub Actions tab (`workflow_dispatch`) — but for the very first run you must authenticate GitHub Actions to GCP somehow, so in practice the **first bootstrap run is usually done locally** with your own `gcloud auth application-default login` credentials, and only *subsequent* bootstrap changes go through the workflow once the WIF secrets already exist.

After apply, copy these outputs into your **GitHub repo secrets**:

| Terraform Output | GitHub Secret Name |
|---|---|
| `github_secret_gcp_wif_provider` | `GCP_WIF_PROVIDER` |
| `github_secret_service_account` | `GCP_SERVICE_ACCOUNT` |
| project id | `GCP_PROJECT_ID` |
| region | `GCP_REGION` |

### Verification

```bash
gsutil ls gs://<bucket_name>              # state bucket exists
gcloud iam workload-identity-pools list --location=global
gcloud iam service-accounts list
```

---

## 8. Infrastructure

The `infra/` root module is the actual platform. It:

- Uses the **GCS backend** created by `bootstrap/` (`infra/backend.tf`, prefix `gke/prod`)
- Declares providers for `google`, `google-beta`, plus **`kubernetes`** and **`helm`** — configured dynamically using the GKE cluster's own endpoint/CA cert as soon as `module.gke` creates it, and the caller's live `google_client_config` access token (so no static kubeconfig is needed)
- Calls all 7 sub-modules in the correct dependency order (see [Resource Flow](#resource-flow))
- Exposes outputs like the Cloud SQL private IP, connection name, backup bucket name, and Artifact Registry URL

Run it exactly like bootstrap, but from the `infra/` directory — or just push to `main` and let `infra.yml` do it.

---

## 9. Module by Module Explanation

### Network (`infra/modules/network`)

Creates:
- A custom-mode **VPC** (no default subnets)
- One **regional subnet** (`10.10.0.0/20`) with two secondary ranges: `pods-range` (`10.20.0.0/16`) and `services-range` (`10.30.0.0/20`) — required for GKE's VPC-native (alias IP) networking
- `private_ip_google_access = true` so nodes without public IPs can still reach Google APIs
- **Cloud Router + Cloud NAT** so private nodes can still reach the internet (e.g., to pull public container images) without themselves having public IPs
- A **private services connection** (VPC peering) to `servicenetworking.googleapis.com`, which is what allows Cloud SQL to get a private IP inside your VPC
- Enables the `container`, `sqladmin`, `secretmanager`, and `servicenetworking` APIs

### IAM (`infra/modules/iam`)

Creates one **dedicated service account per workload** (principle of least privilege), instead of one shared SA:

| Service Account | Used By | Key Roles |
|---|---|---|
| `node_sa` | GKE nodes | logging, monitoring, artifact registry reader |
| `wordpress` | WordPress pod (via Workload Identity) | secretmanager.secretAccessor |
| `external_secrets` | External Secrets Operator | secretmanager.secretAccessor |
| `github_actions` | CI/CD pipeline | (roles granted in `bootstrap/iam.tf`) |
| `jenkins` | Legacy Jenkins experiment (see `archive/`) | — |

Each Kubernetes-facing SA is bound to a Kubernetes Service Account via **Workload Identity** using `google_service_account_iam_member` with member `serviceAccount:<project>.svc.id.goog[<namespace>/<k8s-sa-name>]` — this is what lets a *pod* impersonate a *GCP* service account with zero keys.

### GKE (`infra/modules/gke`)

Creates:
- A **private cluster** (`enable_private_nodes = true`, master on `172.16.0.0/28`) — nodes have no public IPs
- `master_authorized_networks_config` currently open to `0.0.0.0/0` — **temporary/demo setting**, should be locked down to your office/VPN CIDR in real production (see [Security Best Practices](#18-security-best-practices))
- VPC-native networking using the `pods-range` / `services-range` secondary ranges from the network module
- **Workload Identity** enabled (`workload_pool = "<project>.svc.id.goog"`)
- A separate **managed node pool** (default node pool is removed) with autoscaling (2–3 nodes), Shielded VM options, `GKE_METADATA` workload metadata mode, auto-repair and auto-upgrade
- Logging/monitoring via Cloud Operations, HPA and HTTP load balancing add-ons enabled

### Cloud SQL (`infra/modules/cloudsql`)

Creates:
- A **MySQL 8.0** instance with `ipv4_enabled = false` (private IP only, attached to the VPC via the peering created in the network module)
- Automated backups + binary logging enabled
- A **random password** (`random_password` resource, 24 chars) — never hardcoded
- A database and a user for WordPress
- Outputs the password as `sensitive = true` so it never appears in plain text in logs/console output

### Secret Manager (`infra/modules/secret-manager`)

- Creates a secret `wordpress-db-password` with automatic replication
- Stores the Cloud SQL random password as a secret **version** — this is the bridge between "Terraform knows the password" and "Kubernetes can read the password" (via External Secrets Operator, without ever writing it into a Kubernetes YAML file or Git)

### Artifact Registry (`infra/modules/artifact-registry`)

- Creates a Docker-format repository `backup-images` used to store the custom backup CronJob image built from `backup-job/Dockerfile`

### Backup (`infra/modules/backup`)

- Creates a **GCS bucket** (`<project>-sql-backups`) with `public_access_prevention = enforced`, versioning on, and a 30-day lifecycle deletion rule
- Creates a dedicated **backup service account**, bound to Workload Identity as `[wordpress/cloudsql-backup]`
- Grants that SA `roles/cloudsql.admin` (to run SQL export/import) and `roles/storage.objectAdmin` on the backup bucket
- The actual backup **logic** lives outside Terraform, in `backup-job/backup.sh` — it runs `gcloud sql export`, tars the WordPress `uploads/` folder, and uploads both to the bucket. It's triggered by the `backup-cronjob.yaml` Kubernetes CronJob.

---

## 10. GitHub Actions

All three workflows use `permissions: id-token: write` (required for OIDC/WIF) and authenticate with `google-github-actions/auth@v2` — no JSON keys anywhere.

### `bootstrap.yml`

- Trigger: `workflow_dispatch` only (manual, rare)
- Runs `terraform init/fmt/validate/plan/apply` inside `bootstrap/`
- Uploads the plan as an artifact and prints outputs to the Job Summary

### `infra.yml`

- Triggers: push to `main` (path-filtered to `infra/**`), pull requests into `main`, and manual dispatch
- On a **pull request**: runs init → fmt → validate → plan only, and shows the plan in the log — this is your safety net for code review before anything touches real infra
- On **push to main**: additionally runs `apply`, exports outputs as JSON, and uploads the plan, the apply log, and the outputs as workflow artifacts (30-day retention)
- Uses `-parallelism=20` and `-lock-timeout=10m` for faster, safer concurrent-friendly runs

### `terraform-infra-destroy.yml`

- Trigger: manual only, and **gated** — you must type the literal word `DESTROY` into the `confirm` input, otherwise the job doesn't even start (`if: github.event.inputs.confirm == 'DESTROY'`)
- Runs a destroy plan first (so you can see exactly what will be deleted), uploads it, then applies the destroy plan
- Finally lists remaining GKE clusters as a sanity check

---

## 11. Workload Identity Federation (WIF)

**The problem it solves:** Traditionally, GitHub Actions authenticates to GCP using a downloaded service-account JSON key stored as a GitHub Secret. That key never expires on its own, and if it leaks, an attacker has permanent access.

**How WIF works here:**

1. GitHub's OIDC provider issues a short-lived signed JWT token to the workflow run, containing claims like `repository`, `ref`, `actor`.
2. GCP has a **Workload Identity Pool** + **Provider** (created in `bootstrap/main.tf`) configured to trust tokens from `https://token.actions.githubusercontent.com`.
3. The provider's `attribute_condition` restricts trust to **only** `assertion.repository == "your-org/your-repo"` — tokens from any other repository are rejected outright.
4. GCP exchanges that trusted JWT for a **short-lived GCP access token**, scoped to impersonate the `github-actions-sa` service account (via the `roles/iam.workloadIdentityUser` binding).
5. Terraform then runs using that temporary token. It expires automatically — nothing to rotate, nothing to revoke, nothing to leak long-term.

This is the modern, keyless best practice recommended by both GitHub and Google for CI/CD.

---

## 12. Terraform Backend

Both root modules use a **GCS backend**:

```hcl
terraform {
  backend "gcs" {
    bucket = "gke-prod-demo-001-tf-state"
    prefix = "gke/prod"     # infra/backend.tf
    # prefix = "bootstrap"  # bootstrap/backend.tf.backup
  }
}
```

Why remote state instead of a local `terraform.tfstate` file?

- **Shared** — the whole team (or CI) sees the same state, not just your laptop
- **Locking** — GCS backend supports state locking, preventing two `apply` runs from corrupting state simultaneously
- **Durability & versioning** — the bootstrap bucket has `versioning { enabled = true }`, so you can recover a previous state version if something goes wrong
- **Security** — state can contain sensitive values (like the Cloud SQL password); a GCS bucket with `uniform_bucket_level_access` and IAM is far safer than a state file sitting in Git

> Note: `bootstrap/backend.tf.backup` is intentionally named `.backup` (not `.tf`) — this is the classic chicken-and-egg workaround: you comment out/rename the backend config for the *very first* `bootstrap` apply (so it runs with local state), then rename it back to `backend.tf` and run `terraform init -migrate-state` once the bucket exists.

---

## 13. State File

The **state file** (`terraform.tfstate`) is Terraform's internal database — a JSON file mapping every resource block in your `.tf` files to the real-world cloud resource ID it created (e.g., which VPC, which GKE cluster).

Why it matters:

- Terraform uses it to compute the **diff** between "what you declared" and "what actually exists" — this diff is exactly what you see in `terraform plan`
- **Never edit it by hand.** Use `terraform state list`, `terraform state show <resource>`, `terraform state mv`, or `terraform import` instead
- It can contain **secrets in plain text** (e.g., the Cloud SQL `random_password` value) — this is exactly why it lives in a private, IAM-controlled GCS bucket and is never committed to Git
- **State locking**: while one `apply` is running, the backend places a lock so a second concurrent `apply` doesn't run at the same time and corrupt state
- If state is ever lost, Terraform "forgets" it created those resources — it won't delete them automatically, but it will try to recreate everything on the next apply, causing duplicate resources or naming conflicts

---

## 14. Deployment Walkthrough

```bash
# 1. Clone the repo
git clone https://github.com/<you>/gke-infra-terraform.git
cd gke-infra-terraform

# 2. Authenticate locally (for the one-time bootstrap run)
gcloud auth login
gcloud auth application-default login
gcloud config set project <your-project-id>

# 3. Update bootstrap/terraform.tfvars with your project_id, bucket_name, github_repository

# 4. Run bootstrap once
cd bootstrap
terraform init
terraform apply
terraform output   # copy WIF provider + SA email

# 5. Add GitHub repo secrets:
#    GCP_WIF_PROVIDER, GCP_SERVICE_ACCOUNT, GCP_PROJECT_ID, GCP_REGION

# 6. Rename backend.tf.backup -> backend.tf if not already done, then
terraform init -migrate-state

# 7. Update infra/terraform.tfvars with your real project_id/region/zone

# 8. Push to main (or run the "Terraform Infrastructure" workflow manually)
git add . && git commit -m "deploy infra" && git push origin main

# 9. Watch the "infra.yml" workflow run in the GitHub Actions tab

# 10. Once apply succeeds, connect kubectl to the new cluster
gcloud container clusters get-credentials prod-gke-cluster \
  --zone <zone> --project <your-project-id>

kubectl get nodes
```

---

## 15. Verification Commands

```bash
# Terraform
terraform state list
terraform output

# GCP resources
gcloud container clusters list
gcloud container clusters describe prod-gke-cluster --zone <zone>
gcloud sql instances list
gcloud sql instances describe wordpress-db
gcloud secrets list
gcloud secrets versions access latest --secret=wordpress-db-password
gcloud artifacts repositories list
gsutil ls gs://<project>-sql-backups

# Kubernetes
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc,ingress -n wordpress
kubectl get hpa -n wordpress
kubectl get cronjob -n wordpress
kubectl logs -n wordpress job/<backup-job-name>
kubectl describe sa wordpress-sa -n wordpress   # check workload identity annotation
```

---

## 16. Destroy Walkthrough

> Destroys real cloud resources. Double-check the region/project before running.

1. Go to the GitHub Actions tab → **Terraform Destroy** workflow → **Run workflow**
2. In the `confirm` input box, type exactly: `DESTROY`
3. The job first runs `terraform plan -destroy` and uploads it as an artifact — review it if you can before it proceeds
4. It then runs `terraform apply` against the destroy plan and uploads the destroy log
5. Finally it lists remaining GKE clusters as a smoke check

To destroy locally instead:

```bash
cd infra
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
```

> The Cloud SQL instance and state bucket have `force_destroy`/`deletion_protection` set conservatively — read the module code before assuming everything disappears in one shot.

---

## 17. Cost Estimation

Approximate **Mumbai (asia-south1)** monthly costs if left running 24/7 (indicative only — always check the [GCP Pricing Calculator](https://cloud.google.com/products/calculator) for current prices):

| Resource | Approx. Monthly Cost (USD) |
|---|---|
| GKE cluster management fee | ~$74 (or $0 if within the free tier / Autopilot not used here) |
| 2× `e2-medium` nodes | ~$45–55 |
| Cloud NAT (gateway + data processing) | ~$32 + usage |
| Cloud SQL `db-custom-1-3840`, ZONAL, 20GB SSD | ~$60–75 |
| Cloud Storage (state + backups, low volume) | ~$1–5 |
| Artifact Registry (small images) | ~$1–5 |
| Secret Manager | Pennies (per secret version + access) |
| **Rough total** | **~$210–250/month** |

**Cost-saving tips**: use `e2-small` nodes for a demo, scale the node pool down to `min=1`, stop/delete the Cloud SQL instance when not in use, and always run `terraform destroy` when you're done experimenting.

---

## 18. Security Best Practices

- ✅ Already done: keyless CI/CD via **Workload Identity Federation**
- ✅ Already done: Cloud SQL has **no public IP** (`ipv4_enabled = false`)
- ✅ Already done: GKE nodes are **private** (no external IP)
- ✅ Already done: dedicated least-privilege service account **per workload**, not one shared SA
- ✅ Already done: secrets stored in **Secret Manager**, synced via External Secrets Operator — never in Git or plain Kubernetes Secrets manifests
- ⚠️ **To fix before real production**: `master_authorized_networks_config` currently allows `0.0.0.0/0` — restrict this to your office/VPN/CI runner IP ranges
- ⚠️ **To fix before real production**: set `deletion_protection = true` on the GKE cluster and Cloud SQL instance
- ⚠️ Enable **Binary Authorization** and **GKE Policy Controller / OPA Gatekeeper** for supply-chain and policy enforcement
- ⚠️ Turn on **VPC Service Controls** and **Cloud Audit Logs** for the project
- ⚠️ Rotate/limit the broad IAM roles granted to the GitHub Actions SA in `bootstrap/iam.tf` — they're convenient for a learning project but wider than least-privilege for real production (e.g., `roles/resourcemanager.projectIamAdmin` is very powerful)
- ⚠️ Enable **GCS bucket** object versioning + retention policies on the backup bucket (versioning is already on; consider a retention lock too)

---

## 19. Troubleshooting

| # | Issue | Likely Cause | Fix |
|---|---|---|---|
| 1 | `Error: Failed to get existing workspaces: googleapi: Error 404: The specified bucket does not exist` | Bootstrap not applied yet, or wrong bucket name in `backend.tf` | Run `bootstrap/` first; confirm `bucket_name` matches |
| 2 | `Error 403: Permission denied on resource project` during `terraform apply` in CI | GitHub Actions SA missing a role, or WIF provider misconfigured | Re-check `bootstrap/iam.tf` roles and the `attribute_condition` on the WIF provider |
| 3 | `Error: googleapi: Error 409: Requested entity already exists` | Resource created outside Terraform (e.g., manually in Console) or leftover from a partial apply | `terraform import` the existing resource, or delete it manually if it's a duplicate |
| 4 | GitHub Actions: `failed to generate Google Cloud federated token` | `GCP_WIF_PROVIDER` or `GCP_SERVICE_ACCOUNT` secret wrong/missing | Re-copy exact values from `bootstrap` outputs into repo secrets |
| 5 | `terraform init` fails with backend lock error (`Error acquiring the state lock`) | A previous run crashed mid-apply and left a lock | `terraform force-unlock <LOCK_ID>` (use carefully) |
| 6 | GKE cluster stuck in `PROVISIONING` for a long time | Secondary ranges overlap or exhausted, or private service connection not ready | Check `network` module ran fully first (`depends_on`), verify CIDR ranges don't overlap |
| 7 | Cloud SQL `apply` fails: `Error, failed to create instance ... private network required` | The `servicenetworking` peering connection wasn't created before Cloud SQL | Ensure `cloudsql` module depends on `network` (already set in `infra/main.tf`) |
| 8 | Pods can't pull image from Artifact Registry (`ImagePullBackOff`) | Node SA missing `artifactregistry.reader`, or wrong image path/region | Confirm `node_artifact_registry_reader` binding exists; check image URL region prefix |
| 9 | WordPress pod can't connect to MySQL (`Connection refused` / timeout) | Wrong private IP in secret, or Cloud SQL Auth Proxy/private IP not routable yet | Verify `cloudsql_private_ip` output and confirm the pod is in the same VPC via GKE |
| 10 | External Secrets doesn't sync — `SecretSyncedError` | Kubernetes SA not annotated with the right GCP SA / Workload Identity binding mismatch | Check namespace/SA name exactly matches `[wordpress/wordpress-sa]` style binding |
| 11 | `Error: Provider produced inconsistent final plan` | Provider version drift or a resource attribute computed both in Terraform and by GCP | Run `terraform plan` again; pin provider versions in `versions.tf` |
| 12 | `terraform fmt -check` fails the CI pipeline | Someone committed unformatted `.tf` files | Run `terraform fmt -recursive` locally before pushing |
| 13 | `terraform validate` fails: undeclared variable | A `.tfvars` value missing or module input renamed | Check `variables.tf` vs the values passed in `main.tf`/`terraform.tfvars` |
| 14 | HPA shows `<unknown>` for CPU targets | Metrics Server not ready yet, or no resource requests set on the Deployment | Wait a minute after cluster creation; ensure pod `resources.requests.cpu` is set |
| 15 | Backup CronJob pod fails: `Permission denied` calling `gcloud sql export` | Backup SA missing `cloudsql.admin`, or Workload Identity binding not applied | Confirm `backup_cloudsql_admin` role + `backup_workload_identity` resource applied |
| 16 | `terraform apply` in `infra.yml` runs on a PR by mistake | Trigger condition misread | Check the workflow — apply is guarded with `if: github.ref == 'refs/heads/main'` |
| 17 | Destroy workflow does nothing when triggered | Forgot to type `DESTROY` exactly in the confirm input | Re-run and type the literal word `DESTROY` (case-sensitive) |
| 18 | `Error: Error creating NAT: googleapi: Error 400, invalid value for router` | Cloud Router not fully created before NAT resource | Terraform normally handles this via implicit dependency; re-run apply if it's a transient API race |
| 19 | Local `terraform apply` prompts you even though CI works fine | Local `gcloud auth application-default login` credentials lack a role that CI's WIF-derived token has | Grant your own user account the same/adequate roles temporarily, or just use CI |
| 20 | `Error: Instance ... has active operations` | A previous Cloud SQL operation is still in progress | Wait for it to finish (`gcloud sql operations list --instance=<name>`), then retry |
| 21 | `random_password` value changes on every apply unexpectedly | Some upstream input to the module changed, forcing recreation | Compare plan diff carefully; consider `ignore_changes` if genuinely stable |
| 22 | Ingress never gets an external IP | Missing `FrontendConfig`/`BackendConfig` annotations, or GKE ingress controller still provisioning | Give it a few minutes; check `kubectl describe ingress` events |

---

## 20. FAQ

**Q: Why two separate Terraform projects (`bootstrap/` and `infra/`) instead of one?**
A: Because `infra/`'s remote state bucket and CI identity must exist *before* `infra/` can even run — that's the classic chicken-and-egg problem. `bootstrap/` solves it once, manually.

**Q: Why is there no service-account JSON key anywhere in this repo?**
A: Workload Identity Federation lets GitHub Actions get short-lived GCP tokens by presenting its own OIDC identity — no long-lived keys to store, leak, or rotate.

**Q: Can I use this for something other than WordPress?**
A: Yes — the `infra/` platform (VPC, GKE, Cloud SQL, Secret Manager, Artifact Registry, backups) is workload-agnostic. WordPress in `apps/modules/wordpress` is just the reference app; swap it for any container workload.

**Q: Why is the Cloud SQL password generated with `random_password` instead of set manually?**
A: So it's never typed, committed, or shared by hand — Terraform generates it once, stores it in Secret Manager, and only Kubernetes (via Workload Identity) can read it at runtime.

**Q: What's the difference between the `modules/hpa` folder and `infra/modules/`?**
A: `infra/modules/*` are **GCP infrastructure** modules (VPC, GKE, SQL...) used by the `infra/` root module. `modules/hpa` and `apps/modules/*` are **Kubernetes-object** modules (Deployment, HPA, Ingress...) meant to be applied against the cluster once it exists — a different layer of the stack.

**Q: What is `archive/` for?**
A: It holds earlier versions of this project (a Jenkins-on-VM based pipeline and hand-written Kubernetes YAML) kept purely for historical reference — not part of the live pipeline.

**Q: Is this safe to leave running?**
A: It's a demo/learning setup with a few production hardenings still pending — see [Security Best Practices](#18-security-best-practices) before treating it as truly production-grade, and remember it costs real money while running (see [Cost Estimation](#17-cost-estimation)).

---

## 21. Interview Questions

A set of questions this project naturally prepares you to answer — with simple, direct answers.

**1. What problem does a Terraform "bootstrap" project solve?**
Terraform needs a place to store its state file (in a GCS bucket) and GitHub Actions needs an identity to log into GCP. But you can't create that state bucket using Terraform if the state itself needs to live in that same bucket — it's a chicken-and-egg problem. So `bootstrap/` is a small, separate Terraform project you run once, manually, to create the bucket + CI identity first. After that, the main `infra/` project can safely use them.

**2. Explain Workload Identity Federation (WIF). How is it different from a service account key?**
Normally, CI/CD tools log into GCP using a downloaded JSON key — a long-lived secret that never expires on its own and is dangerous if leaked. WIF is different: GitHub gives the workflow a short-lived, signed identity token (OIDC token). GCP trusts this token (only from your specific repo) and exchanges it for a temporary GCP access token. Nothing is stored, nothing to leak, nothing to rotate.

**3. Why does a private GKE cluster still need Cloud NAT?**
"Private" means the nodes have no public IP address. But nodes still need internet access sometimes (like pulling public Docker images). Cloud NAT lets private nodes reach the internet for outgoing traffic only, without giving them a public IP that could be attacked from outside.

**4. What is a GCS backend, and what does state locking prevent?**
A GCS backend means Terraform's state file is stored in a Cloud Storage bucket instead of on your laptop. This lets a team (or CI) share the same state safely. State locking stops two `terraform apply` commands from running at the exact same time — without locking, they could both edit the state and corrupt it.

**5. Why does VPC-native GKE need secondary IP ranges?**
GKE gives every pod and every service its own real IP address inside the VPC (not NAT'd). To do this cleanly, GKE needs two separate address blocks: one for pods (`pods-range`) and one for services (`services-range`), set up in advance on the subnet.

**6. How does Workload Identity let a pod act as a GCP service account?**
Instead of mounting a key file inside the pod, you create a link: "this GCP service account trusts this specific Kubernetes service account, in this specific namespace." When a pod using that Kubernetes SA calls a Google API, GKE automatically gives it a temporary GCP token behind the scenes — no key file, no secret to manage.

**7. Why store the DB password in Secret Manager instead of a plain Kubernetes Secret?**
Kubernetes Secrets are only base64-encoded, not really encrypted, and often end up written in YAML files that get committed to Git by mistake. Secret Manager stores it properly encrypted in Google Cloud, with access control and audit logs. External Secrets Operator then pulls it into the cluster only at runtime.

**8. Why do `terraform plan -out=tfplan` then `terraform apply tfplan` instead of just `terraform apply`?**
This guarantees you apply *exactly* what you reviewed in the plan. If you just run `apply` alone, it re-calculates a fresh plan at that moment — and if something in the cloud changed in between, the plan could differ from what you saw earlier. Saving the plan to a file locks it in.

**9. How would you roll back a bad `terraform apply` in production?**
First, don't panic-delete anything. Check `terraform state list` and `terraform plan` to see the current difference. If you have a previous state version (GCS bucket versioning helps here), you can restore it. Otherwise, fix the `.tf` code to represent the desired state and run `plan`/`apply` again carefully — Terraform is declarative, so the fix is usually "correct the code, then re-apply," not manual console changes.

**10. What does `disable_on_destroy = false` do on `google_project_service`?**
By default, if you delete the Terraform resource that "enabled" an API, Terraform would also disable that API on the project. Setting `disable_on_destroy = false` means: even if this resource is destroyed, keep the API enabled — useful because other things (or other teams) might still depend on that API being on.

**11. Why is `0.0.0.0/0` in `master_authorized_networks_config` a security problem?**
This setting controls which IP addresses are allowed to talk to the Kubernetes API server (the "master"). Setting it to `0.0.0.0/0` means literally anyone on the internet can attempt to connect to your cluster's control plane. It should instead be locked to your office IP, VPN range, or CI runner IP ranges.

**12. Explain the GitHub Actions OIDC → GCP token flow.**
Step by step:
1. Workflow starts, GitHub generates a short-lived OIDC token containing claims like repo name and branch.
2. `google-github-actions/auth` sends this token to GCP's Workload Identity Pool.
3. GCP checks the token is signed by GitHub and matches the `attribute_condition` (correct repo).
4. If it matches, GCP issues a short-lived GCP access token, allowed to impersonate the GitHub Actions service account.
5. Terraform uses that temporary token to talk to GCP APIs.

**13. What happens if the GCS state bucket gets accidentally deleted?**
Terraform loses all memory of what it created — it doesn't know your VPC, GKE cluster, etc. exist anymore. On the next apply, it may try to recreate everything from scratch, causing duplicate resources or naming conflicts. To prevent this: keep bucket versioning on, restrict who can delete the bucket, and take backups. To recover: restore an older state version, or manually `terraform import` existing resources back into a fresh state.

**14. Why use `random_password` instead of a fixed variable for the DB password?**
If the password were a variable with a default value, it would sit in plain text in your `.tf` files and probably get committed to Git. `random_password` generates a strong password automatically at apply time, and it's marked `sensitive = true`, so it's never printed in logs or stored as plain code.

**15. Why use separate service accounts per workload instead of one shared SA?**
This follows the "least privilege" principle. If one service account (say, the WordPress one) gets compromised, the attacker only gets the small set of permissions that account has (like reading one secret) — not full control over the cluster, database, and CI/CD, which would happen if everything shared one powerful account.

---

## 22. Learning Notes

Key takeaways for anyone studying this repo (in short, practical language):

- **Terraform modules = reusable Lego blocks.** Each folder under `infra/modules/` takes inputs (`variables.tf`), creates resources (`main.tf`), and returns values (`outputs.tf`) that other modules can consume — this is how `network`'s `vpc_id` flows into `gke` and `cloudsql` without hardcoding anything.
- **`depends_on` matters even when Terraform can't see an implicit dependency** — e.g., `cloudsql` explicitly depends on `network` because the private-services *peering* isn't referenced directly in any resource attribute, so Terraform wouldn't otherwise know to wait for it.
- **Never store secrets in `.tf` files or `terraform.tfvars` that get committed.** This repo generates the DB password at apply-time and immediately pushes it into Secret Manager — the value never needs to be typed by a human.
- **CI/CD + Terraform = "GitOps for infrastructure."** Every infra change goes through a pull request (plan-only) before an actual apply happens on merge to `main` — the same review discipline as application code.
- **Bootstrap-then-build is a very common real-world pattern**, not unique to this repo — you'll see it in almost every serious multi-environment Terraform setup (dev/staging/prod each need their own state bucket/backend, bootstrapped once).
- **Least privilege isn't optional at scale.** Six different service accounts in `iam/` (node, WordPress, external-secrets, GitHub Actions, Jenkins-legacy, backup) each get *only* the roles they need — if one is compromised, the blast radius is limited to that one identity's permissions.

---

## 23. Future Improvements

- [ ] Add **Prometheus + Grafana** for cluster and app-level observability
- [ ] Add **ArgoCD** to move application deployment (WordPress manifests) to GitOps, separate from infra Terraform
- [ ] Add **Velero** for full cluster/volume-level disaster recovery, complementing the current DB/uploads backup job
- [ ] Enable **Binary Authorization** to only allow signed/verified images to run
- [ ] Add **GKE Policy Controller / OPA Gatekeeper** for org-wide policy enforcement
- [ ] Restrict `master_authorized_networks_config` to specific CIDRs instead of `0.0.0.0/0`
- [ ] Turn on `deletion_protection` for GKE and Cloud SQL for real production use
- [ ] Add automated **restore testing** (currently `restore.sh`/`restore-job.yaml` exist but aren't scheduled/tested automatically)
- [ ] Add a **staging** environment (separate `terraform.tfvars` + backend prefix) before promoting to `prod`
- [ ] Write Terraform **unit/integration tests** (e.g., using `terraform test` or Terratest)

---

*This README was generated to document and explain the `gke-infra-terraform` repository end-to-end — happy learning! 🚀*
