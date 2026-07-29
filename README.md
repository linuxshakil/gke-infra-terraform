# GKE Production Infrastructure on GCP — Terraform Project

A production-style, end-to-end **Infrastructure as Code (IaC)** project that provisions a private GKE cluster on Google Cloud, plus a WordPress workload on top of it, using **four independent Terraform projects** and a fully keyless GitHub Actions CI/CD pipeline.

This README has two goals:
1. Let a **new person clone this repo and actually run it**, end to end.
2. Teach the **Terraform concepts** used here — state, backend, modules, variables, `import`, `-target`, `state mv`, `remote_state`, `taint`, `workspace`, and more — with real examples pulled straight from this codebase, not generic textbook examples.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture](#2-architecture)
3. [Repository Structure](#3-repository-structure)
4. [Technologies Used](#4-technologies-used)
5. [Prerequisites](#5-prerequisites)
6. [Install Everything](#6-install-everything)
7. [Terraform Core Concepts](#7-terraform-core-concepts)
8. [Why Four Separate Terraform Projects?](#8-why-four-separate-terraform-projects)
9. [Bootstrap](#9-bootstrap)
10. [Infrastructure (`infra/`)](#10-infrastructure-infra)
11. [Module by Module Explanation](#11-module-by-module-explanation)
12. [Apps Layer — External Secrets](#12-apps-layer--external-secrets)
13. [Apps Layer — WordPress](#13-apps-layer--wordpress)
14. [Reading Data Across Projects — `terraform_remote_state`](#14-reading-data-across-projects--terraform_remote_state)
15. [GitHub Actions](#15-github-actions)
16. [Workload Identity Federation](#16-workload-identity-federation-wif)
17. [Terraform Backend](#17-terraform-backend)
18. [State File](#18-state-file)
19. [Deployment Walkthrough](#19-deployment-walkthrough)
20. [Verification Commands](#20-verification-commands)
21. [Destroy Walkthrough](#21-destroy-walkthrough)
22. [Cost Estimation](#22-cost-estimation)
23. [Security Best Practices](#23-security-best-practices)
24. [Troubleshooting](#24-troubleshooting)
25. [FAQ](#25-faq)
26. [Interview Questions](#26-interview-questions)
27. [Learning Notes](#27-learning-notes)
28. [Future Improvements](#28-future-improvements)

---

## 1. Introduction

This repository builds a real Kubernetes platform on GCP, split into **four independently-deployable Terraform projects**, each with its **own state file**, its **own GitHub Actions workflow**, and its **own blast radius**:

| # | Root Module | What it owns | Changes how often? |
|---|---|---|---|
| 1 | `bootstrap/` | State bucket + CI/CD identity (WIF) | Once, ever |
| 2 | `infra/` | VPC, GKE cluster, Cloud SQL, IAM, Secret Manager, Artifact Registry, Backups | Rarely |
| 3 | `apps/external-secrets/` | External Secrets Operator (Helm release) | Rarely |
| 4 | `apps/wordpress/` | Namespace, PVC, Deployment, Service, Ingress, static IP, ManagedCertificate, SecretStore, ExternalSecret | Often |

This is an intentional pattern called **layered/composable Terraform**, where infrastructure that changes rarely (VPC, cluster) is isolated from application code that changes often (WordPress image, replicas). Section 8 explains exactly why, and what breaks if you don't do it this way.

> **Repo hygiene update:** earlier iterations of this project had leftover experiments — a Jenkins-VM pipeline, raw Kubernetes YAML, an unused HPA module, and stray root-level `apps/*.tf` files referencing module paths that didn't exist. **All of that has now been removed.** The repo you're reading about here is the clean, active version — four Terraform projects, nothing else.

---

## 2. Architecture

### High-Level Architecture

```
 ┌────────────────────┐        ┌───────────────────────┐
 │   bootstrap/        │──────► │ GCS State Bucket +     │
 │   (run once)        │        │ Workload Identity Pool │
 └────────────────────┘        └───────────┬───────────┘
                                            │ used by all 3 pipelines below
                                            ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │                         infra/  (state: gke/prod)                 │
 │   VPC + Subnet + NAT ──► GKE (private) ──► Cloud SQL (private)     │
 │        │                                        │                  │
 │        ▼                                        ▼                  │
 │   IAM Service Accounts                   Secret Manager             │
 │        │                                        │                  │
 │        ▼                                        ▼                  │
 │   Artifact Registry                      Backup bucket + SA         │
 └───────────────────────────┬───────────────────────────────────────┘
                              │ outputs read via terraform_remote_state
                              ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │           apps/external-secrets/  (state: apps/external-secrets)   │
 │           Helm-installs the External Secrets Operator              │
 └───────────────────────────┬───────────────────────────────────────┘
                              │ operator must exist before ExternalSecret CRs work
                              ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │              apps/wordpress/  (state: apps/wordpress)              │
 │  Namespace → PVC → ServiceAccount(+WI) → Deployment → Service       │
 │       → static IP → Ingress → BackendConfig/FrontendConfig          │
 │       → ManagedCertificate → SecretStore → ExternalSecret           │
 └─────────────────────────────────────────────────────────────────┘
```

### Resource Flow

Within `infra/` (see `infra/main.tf`), dependency order is: `network` → `iam` → `gke` → `cloudsql` → `secret-manager`, with `artifact-registry` and `backup` attaching independently. Full detail in [Module by Module Explanation](#11-module-by-module-explanation).

Across projects, the flow is strictly: **bootstrap → infra → external-secrets → wordpress.** Each later project reads what it needs from the earlier one's **state**, not by re-declaring resources.

### CI/CD Flow

```
git push (paths filtered per folder)
        │
        ▼
Matching GitHub Actions workflow triggers
        │
        ▼
OIDC token → Workload Identity Federation → short-lived GCP token
        │
        ▼
terraform init → fmt -check → validate → plan -out=tfplan
        │
        ├── Pull Request → stop after "terraform show tfplan" (review only)
        │
        └── push to main → terraform apply -auto-approve tfplan
                    │
                    ▼
        Outputs / logs uploaded as workflow artifacts + Job Summary
```

Because each folder has its **own workflow with its own `paths:` filter**, editing `apps/wordpress/**` only ever triggers `wordpress.yml` — it never re-plans the VPC or the database.

---

## 3. Repository Structure

```
gke-infra-terraform/
├── .gitignore                      # ignores state, plans, logs, keys, editor junk (Section 7.9)
│
├── bootstrap/                      # Project 1 — run once, manually
│   ├── main.tf  iam.tf  variables.tf  outputs.tf
│   ├── providers.tf  versions.tf  terraform.tfvars
│   └── backend.tf.backup           # renamed to backend.tf AFTER the bucket exists
│
├── infra/                          # Project 2 — the platform
│   ├── main.tf                     # calls all 7 modules below
│   ├── backend.tf                  # gcs bucket, prefix "gke/prod"
│   ├── variables.tf  outputs.tf  providers.tf  versions.tf  terraform.tfvars
│   └── modules/
│       ├── network/                # VPC, subnet, NAT, private-services peering
│       ├── iam/                    # every service account + IAM bindings
│       ├── gke/                    # private GKE cluster + node pool
│       ├── cloudsql/                # private MySQL instance + random password
│       ├── secret-manager/          # stores DB password as a GCP secret
│       ├── artifact-registry/       # Docker repo for the backup image
│       └── backup/                  # backup bucket + backup service account
│
├── apps/
│   ├── external-secrets/            # Project 3 — its OWN state, backend, providers
│   │   ├── main.tf                  # module "external_secrets" { source = "./modules" }
│   │   ├── backend.tf               # prefix "apps/external-secrets"
│   │   ├── providers.tf  variables.tf  terraform.tfvars  outputs.tf  versions.tf
│   │   └── modules/                 # the actual helm_release resource
│   │
│   └── wordpress/                   # Project 4 — its OWN state, backend, providers
│       ├── main.tf                  # reads infra's remote state, calls ./modules
│       ├── backend.tf               # prefix "apps/wordpress"
│       ├── providers.tf  variables.tf  terraform.tfvars  outputs.tf  versions.tf
│       └── modules/
│           ├── namespace.tf  pvc.tf  service-account.tf  deployment.tf  service.tf
│           ├── ingress.tf  backendconfig.tf  frontendconfig.tf
│           ├── static-ip.tf          # google_compute_global_address "wordpress-ip"
│           ├── managedcertificate.tf # kubernetes_manifest ManagedCertificate
│           ├── secretstore.tf        # kubernetes_manifest SecretStore (Terraform-managed)
│           └── externalsecret.tf     # kubernetes_manifest ExternalSecret (Terraform-managed)
│
├── backup-job/                      # Dockerfile + backup.sh/restore.sh + CronJob + ServiceAccount YAML
└── .github/workflows/
    ├── bootstrap.yml                 # manual — bootstrap/
    ├── infra.yml                     # push/PR on infra/**
    ├── external-secrets.yml          # push/PR on apps/external-secrets/**
    ├── wordpress.yml                 # push/PR on apps/wordpress/**
    └── terraform-infra-destroy.yml   # manual, gated, destroys infra/
```

> **Note on a couple of harmless leftovers still in `apps/wordpress/modules/`:** `secretstore.yaml` and `externalsecret.yaml` are old raw-YAML copies of what `secretstore.tf` and `externalsecret.tf` now create as real `kubernetes_manifest` resources. They're not applied by Terraform (only `.tf` files are), so they're inert reference copies — safe to delete whenever you like, exactly like the root `apps/*.tf` files you already removed. Same for `secret.tf-backup` — a disabled, non-`.tf`-extension backup of an old Kubernetes Secret resource, superseded by the ExternalSecret approach.

---

## 4. Technologies Used

| Category | Tool |
|---|---|
| IaC | Terraform ≥ 1.15 |
| Cloud Provider | Google Cloud Platform (GCP) |
| Container Orchestration | Google Kubernetes Engine (GKE), private cluster |
| Database | Cloud SQL for MySQL (private IP only) |
| Secrets | Google Secret Manager + External Secrets Operator |
| Container Registry | Artifact Registry |
| CI/CD | GitHub Actions (4 separate workflows) |
| Auth (CI → Cloud) | Workload Identity Federation (OIDC, keyless) |
| App Workload | WordPress (Deployment, PVC, Service, Ingress, ManagedCertificate) |
| Backup | Custom Docker image + Kubernetes CronJob + Cloud Storage |
| Terraform Providers | `google`, `google-beta`, `kubernetes`, `helm`, `kubectl`, `random` |

---

## 5. Prerequisites

- A GCP project with billing enabled
- Owner (or equivalent) role — needed only for the very first, manual `bootstrap` run
- A GitHub repository to push this code to
- A registered domain (e.g. from BigRock)
- Comfort with a terminal

You do **not** need a running Kubernetes cluster — Terraform builds it.

---

## 6. Install Everything

### Terraform

```bash
# Linux
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# macOS
brew tap hashicorp/tap && brew install hashicorp/tap/terraform

terraform -version   # >= 1.15.0
```

### gcloud

```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
gcloud auth login
gcloud auth application-default login   # needed for local terraform runs
```

### kubectl

```bash
gcloud components install kubectl
kubectl version --client
```

### Git

```bash
sudo apt install git      # Linux
brew install git          # macOS
```

---

## 7. Terraform Core Concepts

This section explains the Terraform mechanics used throughout this repo, with **real commands you can run against this exact project**.

### 7.1 `init`, `plan`, `apply`, `destroy` — the core loop

```bash
cd infra
terraform init      # downloads providers, connects to the backend, reads .terraform.lock.hcl
terraform plan       # shows WHAT WOULD CHANGE — nothing is touched yet
terraform apply      # actually creates/updates real GCP resources
terraform destroy    # actually deletes them
```

`plan` is a **dry run** — it computes the difference between your `.tf` code and the current state, and prints it as `+ create`, `~ update in-place`, `- destroy`. Always read a plan before approving an apply.

### 7.2 Variables and `.tfvars` — and why they matter

Every module in this repo separates **what can change** (`variables.tf`) from **the actual values** (`terraform.tfvars`). Example, from `infra/variables.tf`:

```hcl
variable "project_id" {
  type = string
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}
```

And `infra/terraform.tfvars` supplies the real values:

```hcl
project_id   = "gke-prod-demo-001"
machine_type = "e2-small"
```

**Why separate them?** So the *same* module code (`main.tf`) can be reused for dev/staging/prod just by swapping `.tfvars` files — you never edit the logic, only the inputs. Terraform resolves variable values in this **order of precedence** (highest wins):

1. `-var="key=value"` on the CLI
2. `-var-file=custom.tfvars` on the CLI
3. `*.auto.tfvars` (auto-loaded)
4. `terraform.tfvars` (auto-loaded — what this repo uses)
5. `TF_VAR_key` environment variables
6. The `default` inside `variable {}` (lowest priority)

Example — overriding the machine type just for one run without touching any file:

```bash
terraform plan -var="machine_type=e2-medium"
```

### 7.3 Modules — how "calling a module" actually works

A **module** is just a folder of `.tf` files. `infra/main.tf` calls the network module like this:

```hcl
module "network" {
  source = "./modules/network"     # path to the folder

  project_id   = var.project_id    # values flow IN as inputs...
  cluster_name = var.cluster_name
  region       = var.region
}
```

Inside `infra/modules/network/variables.tf`, those same names (`project_id`, `cluster_name`, `region`) must be declared as `variable` blocks — that's the module's "parameter list." Its `output.tf` then exposes values back OUT:

```hcl
# infra/modules/network/output.tf
output "vpc_id" {
  value = google_compute_network.vpc.id
}
```

...which `infra/main.tf` consumes in another module call:

```hcl
module "gke" {
  source    = "./modules/gke"
  vpc_id    = module.network.vpc_id   # output of one module → input of another
  subnet_id = module.network.subnet_id
}
```

This is exactly how `network` → `gke` → `cloudsql` are wired together — **outputs flowing into inputs**, never resources copy-pasted between folders.

### 7.4 `terraform state` — inspecting what Terraform thinks exists

The state file is Terraform's map of "resource block → real cloud object." You almost never edit it by hand, but you inspect it constantly:

```bash
# List every resource Terraform is tracking in this project
terraform state list

# Example output from infra/:
# module.network.google_compute_network.vpc
# module.gke.google_container_cluster.primary
# module.cloudsql.google_sql_database_instance.wordpress_db

# Show full details of one resource
terraform state show module.gke.google_container_cluster.primary

# Rename/move a resource address without destroying+recreating it
terraform state mv module.gke.google_container_cluster.primary \
                    module.gke.google_container_cluster.main
```

`state mv` matters because if you rename a resource in your `.tf` code without telling Terraform, it plans to **destroy the old one and create a new one** — on a live GKE cluster, that's catastrophic. `state mv` tells Terraform "this is the same object, just a new address," with zero real-world changes.

### 7.5 `terraform import` — adopting a resource that already exists

```bash
# 1. Write the resource block in .tf first (matching what already exists)
resource "google_artifact_registry_repository" "backup_images" {
  location      = "asia-south1"
  repository_id = "backup-images"
  format        = "DOCKER"
}

# 2. Import the real GCP object into that resource address
terraform import module.artifact_registry.google_artifact_registry_repository.backup_images \
  projects/gke-prod-demo-001/locations/asia-south1/repositories/backup-images

# 3. Plan should now show "no changes" if your .tf matches reality
terraform plan
```

`import` only populates the **state** — you still write the matching `.tf` code yourself, or `plan` will show a confusing diff trying to "fix" attributes you didn't declare.

### 7.6 Targeted apply — changing only a few resources

```bash
terraform plan  -target=module.backup
terraform apply -target=module.backup
```

`-target` is a **safety valve for emergencies or debugging**, not routine practice — Hashicorp warns it can leave state and configuration out of sync if overused. Always follow it with a normal, full `terraform plan` to confirm nothing else drifted.

### 7.7 Backend importance & `-migrate-state`

`bootstrap/backend.tf.backup` vs `infra/backend.tf` is a deliberate example:

- `bootstrap/` initially has **no active backend** (the `.backup` extension means Terraform ignores it) → its first-ever state is stored **locally**, because the GCS bucket it's about to create doesn't exist yet.
- Once `bootstrap` creates the bucket, you rename `backend.tf.backup` → `backend.tf` and run:

```bash
terraform init -migrate-state
```

Terraform detects the backend configuration changed (none → gcs) and offers to **copy your existing local state into the new remote backend** — nothing in the cloud is recreated, only where the state file *lives* changes. This exact pattern is why `bootstrap` and `infra` cannot be the same Terraform project.

### 7.8 Outputs — the "return values" of a project

`infra/outputs.tf` exposes values other projects need:

```hcl
output "cloudsql_private_ip" {
  value = module.cloudsql.private_ip
}
```

`apps/wordpress/main.tf` reads these across a completely separate Terraform project using `terraform_remote_state` (full explanation in [Section 14](#14-reading-data-across-projects--terraform_remote_state)).

### 7.9 `.gitignore` for a Terraform repo — why it's not optional

This repo's `.gitignore` ignores several Terraform-specific categories that are easy to forget:

- **State files** (`*.tfstate`, `*.tfstate.backup`) — never belong in Git even though this repo uses a remote backend; a stray local one could still leak the Cloud SQL password in plain text.
- **Plan files** (`*.tfplan`, `tfplan`, `destroy.tfplan`) — binary snapshots of a proposed change, regenerated every CI run; committing them is both useless and a potential secrets leak (a plan can contain sensitive attribute values).
- **Lock-info files** (`.terraform.tfstate.lock.info`) — left behind if a local apply crashes mid-run.
- **`.terraform/` directories** — provider binaries and cached modules, re-downloaded by `terraform init` every time; committing them bloats the repo for no benefit.
- **`.terraform.lock.hcl` is the one exception that SHOULD be committed** (it's not in this repo's ignore list) — it pins exact provider versions so everyone (and CI) gets identical, reproducible provider installs. Don't confuse it with the files above.

### 7.10 A few more commands worth knowing

```bash
terraform validate          # checks syntax + internal consistency, no cloud calls
terraform fmt -recursive    # auto-formats every .tf file consistently (this repo's CI enforces -check)
terraform providers         # shows every provider (and version) each module actually requires
terraform graph             # outputs a dependency graph (pipe into Graphviz to visualize module order)
terraform console           # an interactive REPL — e.g. type module.network.vpc_id to test an expression
terraform apply -replace="module.gke.google_container_node_pool.primary"
                             # forces recreation of ONE resource without editing .tf (replaces the old `terraform taint`)
```

### 7.11 Variables & Outputs — How They Actually Flow, Module by Module (simple English)

This is the same "input → variable → resource → output" pattern repeated everywhere in this repo. Once you see it once, you can read any module in five seconds. Here it is walked through for real modules in this codebase:

**Inside `infra/` — one module feeding the next**

| Step | What happens |
|---|---|
| 1 | `infra/terraform.tfvars` has plain values like `project_id = "gke-prod-demo-001"`. |
| 2 | `infra/variables.tf` declares `variable "project_id" {}` so Terraform knows this name is allowed and what type it expects. |
| 3 | `infra/main.tf` calls `module "network" { project_id = var.project_id }` — this is Terraform copying that value **into** the network module. |
| 4 | Inside `infra/modules/network/variables.tf`, there's a matching `variable "project_id" {}` — this is the module's own "parameter," completely separate from the root one, just sharing a name for clarity. |
| 5 | The network module creates the VPC, and its `output.tf` exposes `output "vpc_id" { value = google_compute_network.vpc.id }` — this is the module **returning** a value to whoever called it. |
| 6 | Back in `infra/main.tf`, the next module call reads it: `module "gke" { vpc_id = module.network.vpc_id }` — the output of one module becomes the input of the next. |

Same pattern repeats for `iam` → `gke` (node service account email flows in), and `network` → `cloudsql` (VPC ID needed for the private connection).

**Across projects — `infra` "returns" a value, `apps/wordpress` "receives" it**

| Step | What happens |
|---|---|
| 1 | `infra/outputs.tf` declares `output "wordpress_gsa_email" { value = module.iam.wordpress_gsa_email }` — this makes the value visible **outside** the `infra` project entirely, once `infra` is applied. |
| 2 | `apps/wordpress/main.tf` has a `data "terraform_remote_state" "infra" { ... }` block — this is Terraform reading `infra`'s *entire state file* from the shared GCS bucket, from a different project, as read-only data. |
| 3 | `apps/wordpress/main.tf` then writes `module "wordpress" { gcp_service_account = data.terraform_remote_state.infra.outputs.wordpress_gsa_email }` — pulling that one specific output value out and feeding it into its own module call. |
| 4 | Inside `apps/wordpress/modules/variables.tf`, there's a `variable "gcp_service_account" {}` waiting to receive it — same "parameter" pattern as inside `infra/`, just crossing a project boundary instead of a module boundary. |
| 5 | `apps/wordpress/modules/service-account.tf` then actually uses `var.gcp_service_account` inside a Kubernetes annotation, to link the Kubernetes ServiceAccount to that exact GCP service account. |

**The one-sentence version:** a `variable` is always "a value coming IN," an `output` is always "a value going OUT," and a `module` call (or a `terraform_remote_state` block) is simply the wire connecting one project/module's OUT to another's IN.

---

## 8. Why Four Separate Terraform Projects?

A very common beginner mistake is putting *everything* — VPC, GKE, database, AND the WordPress app — into one `main.tf`. This repo deliberately avoids that, for reasons you can see directly in the code:

| Concern | If everything is 1 project | This repo's approach |
|---|---|---|
| Blast radius | A typo in the WordPress image tag can trigger a plan touching your VPC/database too | `apps/wordpress` has its own state — a bad WordPress change can't even see the VPC's resource addresses |
| State size & lock contention | One huge state file, one lock — two people can't work on different layers simultaneously | 4 state files under different `prefix` values in the same bucket, each locked independently |
| Deploy frequency mismatch | Infra changes monthly, app changes daily — but you'd `plan` the whole thing every time | 4 separate GitHub Actions workflows, each with its own `paths:` filter, so unrelated layers never even run |
| Ownership | One team owns everything | Platform team owns `bootstrap`/`infra`; app team owns `apps/wordpress` |
| First-run chicken-and-egg | Can't create the state bucket using state stored in that bucket | `bootstrap` solves it once, with local state |

Each `apps/*` project still needs facts from `infra` (the DB's private IP, the GSA email, etc.) — it gets them by **reading `infra`'s state as data**, not by re-declaring those resources. That's exactly what `terraform_remote_state` is for (Section 14).

---

## 9. Bootstrap

### Why Bootstrap?

Terraform needs a remote place to store state, and GitHub Actions needs an identity to talk to GCP — but you can't create the state bucket *using* Terraform state that would need to live in that very bucket. `bootstrap/` is a small, separate project run **once, manually**, to break that cycle.

### Resources Created

From `bootstrap/main.tf` + `bootstrap/iam.tf`:
- Required APIs (`iam`, `iamcredentials`, `cloudresourcemanager`, `sts`, `storage`)
- A **versioned GCS bucket** for all future Terraform state (shared by `infra` and both `apps/*` projects, via different `prefix` values)
- A **GitHub Actions service account**
- A **Workload Identity Pool + Provider**, restricted to your specific GitHub repo via `attribute_condition`
- Project IAM roles granted to the GitHub Actions SA — everything `infra` and `apps/*` pipelines will ever need

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

Copy these outputs into your GitHub repo's **Settings → Secrets and variables → Actions**:

| Terraform Output | GitHub Secret |
|---|---|
| WIF provider resource name | `GCP_WIF_PROVIDER` |
| GitHub Actions SA email | `GCP_SERVICE_ACCOUNT` |
| project id | `GCP_PROJECT_ID` |
| region | `GCP_REGION` |

### Verification

```bash
gsutil ls gs://<bucket_name>
gcloud iam workload-identity-pools list --location=global
gcloud iam service-accounts list
```

---

## 10. Infrastructure (`infra/`)

`infra/backend.tf` points at `prefix = "gke/prod"` in the shared bucket. `infra/providers.tf` configures `google`, `google-beta`, and dynamically configures `kubernetes`/`helm` using the freshly-created GKE cluster's own endpoint + `google_client_config` token — no static kubeconfig needed.

`infra/main.tf` calls all 7 modules in dependency order (see Section 11), and `infra/outputs.tf` exposes everything `apps/*` will need later: `cloudsql_private_ip`, `database_name`, `database_user`, `database_password` (sensitive), `node_service_account`, `backup_bucket_name`, `artifact_registry`, etc.

Run it exactly like bootstrap, from `infra/`, or just push to `main` and let `infra.yml` do it.

---

## 11. Module by Module Explanation

### Network (`infra/modules/network`)

Custom-mode VPC, one regional subnet with two secondary ranges (`pods-range`, `services-range`) for VPC-native GKE, Cloud Router + Cloud NAT (so private nodes can still reach the internet), and a private-services VPC peering that lets Cloud SQL get a private IP.

### IAM (`infra/modules/iam`)

One dedicated service account **per workload** (least privilege) — `node_sa`, `wordpress` (`wordpress-gsa`), `external_secrets` (`external-secrets-gsa`), `github_actions`, `jenkins` (kept for historical reasons — the Jenkins-VM experiment itself has been removed from the repo, but its IAM binding remains harmless if unused). Each Kubernetes-facing SA is bound to a namespaced Kubernetes ServiceAccount via Workload Identity:

```hcl
resource "google_service_account_iam_member" "wordpress_workload_identity" {
  service_account_id = google_service_account.wordpress.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "serviceAccount:${var.project_id}.svc.id.goog[wordpress/wordpress-sa]"
}
```

> ✅ **Fixed:** `infra/outputs.tf` now exposes `output "wordpress_gsa_email" { value = module.iam.wordpress_gsa_email }` at the root level, and `apps/wordpress/main.tf` now passes `data.terraform_remote_state.infra.outputs.wordpress_gsa_email` into `gcp_service_account` (previously it mistakenly used `node_service_account`, the GKE **node** SA, which was never granted `roles/secretmanager.secretAccessor`). Verified on a live cluster: `kubectl describe sa wordpress-sa -n wordpress` now correctly shows the annotation `iam.gke.io/gcp-service-account: wordpress-gsa@<project>.iam.gserviceaccount.com`.

### GKE (`infra/modules/gke`)

Private cluster (`enable_private_nodes = true`), VPC-native networking using the network module's secondary ranges, Workload Identity enabled (`<project>.svc.id.goog`), a separate managed, autoscaling node pool (default node pool removed).

### Cloud SQL (`infra/modules/cloudsql`)

Private-IP-only MySQL instance (`ipv4_enabled = false`), automated backups, and a `random_password` resource (`sensitive = true`) — never hardcoded anywhere.

### Secret Manager (`infra/modules/secret-manager`)

Stores the Cloud SQL `random_password` as a secret (`wordpress-db-password`) — the bridge between "Terraform generated the password" and "Kubernetes can read it later," without it ever touching a YAML file or Git.

### Artifact Registry (`infra/modules/artifact-registry`)

A Docker-format repository for the custom backup CronJob image.

### Backup (`infra/modules/backup`)

A GCS bucket with `public_access_prevention = enforced`, versioning, and a 30-day lifecycle rule, plus a dedicated backup service account bound to Workload Identity as `[wordpress/cloudsql-backup]` — matching the `backup-job/serviceaccount.yaml` Kubernetes ServiceAccount used by the actual backup CronJob.

---

## 12. Apps Layer — External Secrets

### What problem does this solve?

A normal Kubernetes `Secret` has two weaknesses:
1. It is only **base64-encoded**, not encrypted — anyone with cluster access can run `kubectl get secret -o yaml` and read the real value.
2. If you write that Secret into a YAML file and commit it to Git, the password sits in your Git history forever.

**External Secrets Operator (ESO)** fixes this. It's a small controller that runs inside the cluster and **fetches the real secret live from GCP Secret Manager**, then creates a normal Kubernetes Secret from it automatically — no human ever copies or pastes a password.

### How it fits together in this repo

```
Terraform generates a random DB password (infra/modules/cloudsql/password.tf)
        │
        ▼
Terraform stores that password in GCP Secret Manager (infra/modules/secret-manager)
        │
        ▼
apps/external-secrets installs the ESO controller into the cluster (via Helm)
        │
        ▼
apps/wordpress/modules/secretstore.tf tells ESO: "connect to GCP Secret Manager,
                                                    in this project"
        │
        ▼
apps/wordpress/modules/externalsecret.tf tells ESO: "fetch the 'wordpress-db-password'
                                                        secret and create a Kubernetes
                                                        Secret named 'wordpress-db' from it"
        │
        ▼
apps/wordpress/modules/deployment.tf mounts that 'wordpress-db' Secret into the
                                       WordPress container as an environment variable
```

### Two different objects in the code

**1. `SecretStore`** (`secretstore.tf`) — the "connection config." It just says which backend to talk to:

```hcl
spec = {
  provider = {
    gcpsm = {
      projectID = "gke-prod-demo-001"
    }
  }
}
```

**2. `ExternalSecret`** (`externalsecret.tf`) — says what to fetch and where to put it:

```hcl
spec = {
  secretStoreRef = { name = "gcp-secretmanager" }
  target = { name = "wordpress-db" }               # the Kubernetes Secret that gets created
  data = [{
    secretKey = "password"                          # the key inside that Kubernetes Secret
    remoteRef = { key = "wordpress-db-password" }    # the actual secret name in Secret Manager
  }]
}
```

`refreshInterval = "1h"` means ESO re-checks Secret Manager every hour. If the password ever rotates, the Kubernetes Secret updates automatically — no manual step needed.

### Workload Identity's role here

The ESO controller itself needs to talk to GCP, so it uses its own GCP service account (`external-secrets-gsa`), bound via Workload Identity:

```
serviceAccount:<project>.svc.id.goog[external-secrets/external-secrets]
```

That service account is granted `roles/secretmanager.secretAccessor` (in `infra/modules/iam/external-secrets.tf`). This means the ESO pod authenticates to GCP automatically through GKE — no key file needed anywhere.

### Why is this its own separate Terraform project?

Because ESO is an **infrastructure-level operator** — it's installed once for the whole cluster and rarely changes (maybe a version bump now and then). WordPress, on the other hand, is an **application** that changes often. That's why `external-secrets.yml` and `wordpress.yml` are two separate pipelines, and why `apps/external-secrets` must always be deployed **before** `apps/wordpress` — the `SecretStore`/`ExternalSecret` custom resources WordPress needs are only recognized by the cluster once ESO's own CRDs and controller already exist.

---

`apps/external-secrets/` is its **own root Terraform project**:

```hcl
# apps/external-secrets/main.tf
module "external_secrets" {
  source     = "./modules"
  project_id = var.project_id
}
```

```hcl
# apps/external-secrets/modules/main.tf
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.19.2"
}
```

Its `backend.tf` uses `prefix = "apps/external-secrets"` — a **separate state file** in the same bucket, so this operator can be upgraded independently of everything else. It must be applied **before** `apps/wordpress`, because WordPress's `SecretStore`/`ExternalSecret` custom resources need the operator's CRDs and controller already running.

---

## 13. Apps Layer — WordPress

`apps/wordpress/` is the fourth independent project. Its `main.tf` reads `infra`'s state and calls `./modules`:

```hcl
data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = "gke-prod-demo-001-tf-state"
    prefix = "gke/prod"
  }
}

module "wordpress" {
  source      = "./modules"
  db_host     = data.terraform_remote_state.infra.outputs.cloudsql_private_ip
  db_name     = data.terraform_remote_state.infra.outputs.database_name
  db_user     = data.terraform_remote_state.infra.outputs.database_user
  db_password = data.terraform_remote_state.infra.outputs.database_password
  domain      = "myahad.online"
  gcp_service_account = data.terraform_remote_state.infra.outputs.wordpress_gsa_email   # fixed — was node_service_account
}
```

Inside `apps/wordpress/modules/`, resources are created in this order: `namespace.tf` → `pvc.tf` → `service-account.tf` (Workload Identity annotation) → `deployment.tf` → `service.tf` → `static-ip.tf` (reserves the `wordpress-ip` global address) → `ingress.tf` (GCE ingress, referencing that static IP + a managed cert name) → `backendconfig.tf` / `frontendconfig.tf` (health checks + HTTPS redirect) → `managedcertificate.tf` (the actual cert CRD, tied to `var.domain`) → `secretstore.tf` + `externalsecret.tf` (real `kubernetes_manifest` Terraform resources — the `.yaml` copies sitting alongside them are inert leftovers, see Section 3 note).

---

## 14. Reading Data Across Projects — `terraform_remote_state`

This is the concept that makes 4-independent-projects actually work without copy-pasting values. Any project can read another project's **outputs** as if they were local data:

```hcl
data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = "gke-prod-demo-001-tf-state"   # same bucket bootstrap created
    prefix = "gke/prod"                     # infra's specific state path
  }
}

# then reference any output infra/outputs.tf declared:
data.terraform_remote_state.infra.outputs.cloudsql_private_ip
data.terraform_remote_state.infra.outputs.database_name
```

Important properties:
- It's **read-only** — `apps/wordpress` cannot modify `infra`'s resources, only read its outputs.
- It creates an **implicit dependency on values**, not on apply order — if `infra` hasn't been applied yet, these outputs simply won't exist and `terraform plan` in `apps/wordpress` will fail. You must always `apply` in the order: `bootstrap` → `infra` → `external-secrets` → `wordpress`.
- Sensitive outputs (like `database_password`, marked `sensitive = true` in `infra/outputs.tf`) stay marked sensitive when read this way — they won't print in `apps/wordpress`'s plan/apply logs either.

---

## 15. GitHub Actions

All workflows authenticate via `google-github-actions/auth@v2` using WIF — no JSON keys anywhere.

| Workflow | Trigger | Working directory | Notes |
|---|---|---|---|
| `bootstrap.yml` | `workflow_dispatch` only | `bootstrap/` | Manual, rare |
| `infra.yml` | push/PR on `infra/**` | `infra/` | PR = plan only; push to `main` = apply |
| `external-secrets.yml` | push/PR on `apps/external-secrets/**` | `apps/external-secrets/` | Independent state/lock from infra |
| `wordpress.yml` | push/PR on `apps/wordpress/**` | `apps/wordpress/` | Most frequently triggered pipeline |
| `terraform-infra-destroy.yml` | manual, gated by typing `DESTROY` | `infra/` | Runs a destroy plan first, uploads it, then applies it |

Because each workflow filters on its own `paths:`, a WordPress deployment.yaml change **never** re-plans your VPC, and a network change **never** touches WordPress.

---

## 16. Workload Identity Federation (WIF)

Instead of a long-lived service-account JSON key in GitHub Secrets:

1. GitHub's OIDC provider issues a short-lived signed token to the running workflow.
2. GCP's **Workload Identity Pool Provider** (created in `bootstrap/`) trusts tokens from `token.actions.githubusercontent.com`, restricted by `attribute_condition = "assertion.repository == '<owner>/<repo>'"`.
3. GCP exchanges the token for a short-lived GCP access token scoped to impersonate the GitHub Actions service account.
4. Terraform uses that temporary token. It expires on its own — nothing to rotate or leak.

---

## 17. Terraform Backend

Every one of the 4 projects uses a **GCS backend**, in the **same bucket**, but with a **different `prefix`** — this is how one bucket safely holds 4 separate, independently-locked state files:

| Project | `prefix` |
|---|---|
| `bootstrap` | (local, until first apply; then `bootstrap`) |
| `infra` | `gke/prod` |
| `apps/external-secrets` | `apps/external-secrets` |
| `apps/wordpress` | `apps/wordpress` |

Remote state gives you: **sharing** (whole team/CI sees the same state), **locking** (two applies can't corrupt the same prefix simultaneously), **versioning** (recover an older state version if something breaks), and **security** (IAM-controlled bucket instead of a state file floating around in Git, which could contain the Cloud SQL password in plain text).

---

## 18. State File

The state file maps every `.tf` resource block to the real GCP/Kubernetes object it created. Terraform uses it to compute every `plan`'s diff.

Golden rules:
- **Never hand-edit it.** Use `terraform state list / show / mv`, or `terraform import`.
- It can contain **secrets in plain text** (e.g. the Cloud SQL password appears in `infra`'s state) — this is exactly why it lives in a private, IAM-controlled GCS bucket, never in Git (and exactly why `.gitignore` blocks `*.tfstate*`, see Section 7.9).
- **Locking**: while one `apply` runs against a given prefix, the backend locks it so a second concurrent apply against the *same* state can't corrupt it. Different prefixes (e.g. `infra` vs `apps/wordpress`) lock independently — they can run at the same time safely.
- If state is lost, Terraform "forgets" what it created — it won't auto-delete real resources, but will likely try to recreate them on the next apply, causing duplicates or naming conflicts.

---

## 19. Deployment Walkthrough

```bash
# 1. Clone
git clone https://github.com/<you>/gke-infra-terraform.git
cd gke-infra-terraform

# 2. Local auth (for the one-time bootstrap run)
gcloud auth login
gcloud auth application-default login
gcloud config set project <your-project-id>

# 3. bootstrap — creates state bucket + WIF identity
cd bootstrap
terraform init && terraform apply
terraform output   # copy these into GitHub secrets (see Section 9)
cd ..

# 4. Add repo secrets: GCP_WIF_PROVIDER, GCP_SERVICE_ACCOUNT, GCP_PROJECT_ID, GCP_REGION

# 5. infra — the platform
cd infra
terraform init
terraform apply
cd ..
# (or just push to main and let infra.yml run it)

# 6. apps/external-secrets — the operator (must come before wordpress)
cd apps/external-secrets
terraform init && terraform apply
cd ../..

# 7. apps/wordpress — the actual site
cd apps/wordpress
terraform init && terraform apply
cd ../..

# 8. Get the static IP Terraform reserved
gcloud compute addresses describe wordpress-ip --global --format="get(address)"

# 9. In your domain registrar's DNS panel, add:
#    A record, Host "@",   Value <static IP>
#    A record, Host "www", Value <static IP>

# 10. Wait for the managed certificate to go Active (needs DNS to resolve first)
kubectl get managedcertificate wordpress-cert -n wordpress -w

# 11. Connect kubectl and verify
gcloud container clusters get-credentials prod-gke-cluster --zone <zone>
kubectl get pods -n wordpress
```

---

## 20. Verification Commands

A quick sanity pass (`terraform state list` + a couple of `gcloud`/`kubectl` commands) per project:

```bash
# Terraform (run inside the relevant folder)
terraform state list
terraform output
```

Below is a **resource-by-resource guide** — for every real resource each module creates, the exact command to confirm it actually exists and is configured correctly.

### `infra/modules/network`

| Resource | Verify with |
|---|---|
| VPC | `gcloud compute networks describe prod-gke-vpc` |
| Subnet + secondary ranges | `gcloud compute networks subnets describe <subnet-name> --region asia-south1` — check `secondaryIpRanges` shows `pods-range` and `services-range` |
| Cloud Router | `gcloud compute routers describe <router-name> --region asia-south1` |
| Cloud NAT | `gcloud compute routers nats describe <nat-name> --router=<router-name> --region asia-south1` |
| Private services peering | `gcloud services vpc-peerings list --network=prod-gke-vpc` |

### `infra/modules/iam`

| Resource | Verify with |
|---|---|
| All service accounts (node, wordpress, external-secrets, github-actions, jenkins) | `gcloud iam service-accounts list --project=<project-id>` |
| Node SA's project roles | `gcloud projects get-iam-policy <project-id> --flatten="bindings[].members" --filter="bindings.members:prod-gke-cluster-node-sa*"` |
| WordPress SA's Secret Manager role | `gcloud projects get-iam-policy <project-id> --flatten="bindings[].members" --filter="bindings.members:wordpress-gsa*"` |
| Workload Identity binding (wordpress) | `gcloud iam service-accounts get-iam-policy wordpress-gsa@<project-id>.iam.gserviceaccount.com` — look for `roles/iam.workloadIdentityUser` with member `...svc.id.goog[wordpress/wordpress-sa]` |

### `infra/modules/gke`

| Resource | Verify with |
|---|---|
| Cluster (private) | `gcloud container clusters describe prod-gke-cluster --zone <zone>` — check `privateClusterConfig.enablePrivateNodes: true` |
| Node pool | `gcloud container node-pools describe <pool-name> --cluster prod-gke-cluster --zone <zone>` |
| Workload Identity enabled | Same `describe` output — check `workloadIdentityConfig.workloadPool` |
| Nodes actually up | `kubectl get nodes -o wide` (after `gcloud container clusters get-credentials`) |

### `infra/modules/cloudsql`

| Resource | Verify with |
|---|---|
| SQL instance (private IP only) | `gcloud sql instances describe wordpress-db` — check `ipAddresses` has no `PRIMARY`/public entry, and `settings.ipConfiguration.ipv4Enabled: false` |
| Database | `gcloud sql databases list --instance=wordpress-db` |
| User | `gcloud sql users list --instance=wordpress-db` |
| Random password (never logged in plain text) | `terraform output -json database_password` (from `infra/`) — will show as a redacted/sensitive value in the CLI; only pipe to a file if you genuinely need it |

### `infra/modules/secret-manager`

| Resource | Verify with |
|---|---|
| Secret exists | `gcloud secrets describe wordpress-db-password` |
| Secret has a version with the DB password | `gcloud secrets versions access latest --secret=wordpress-db-password` |

### `infra/modules/artifact-registry`

| Resource | Verify with |
|---|---|
| Docker repository | `gcloud artifacts repositories describe backup-images --location=asia-south1` |
| Images pushed to it | `gcloud artifacts docker images list asia-south1-docker.pkg.dev/<project-id>/backup-images` |

### `infra/modules/backup`

| Resource | Verify with |
|---|---|
| GCS bucket | `gcloud storage buckets describe gs://<project-id>-sql-backups` — check `public_access_prevention: enforced` and versioning |
| Backup service account | `gcloud iam service-accounts describe cloudsql-backup-sa@<project-id>.iam.gserviceaccount.com` |
| Workload Identity binding | `gcloud iam service-accounts get-iam-policy cloudsql-backup-sa@<project-id>.iam.gserviceaccount.com` — look for member `...svc.id.goog[wordpress/cloudsql-backup]` |
| Actual backup files landing there | `gcloud storage ls gs://<project-id>-sql-backups/` |

### `apps/external-secrets`

| Resource | Verify with |
|---|---|
| Helm release itself | `helm list -n external-secrets` |
| Operator pods running | `kubectl get pods -n external-secrets` |
| CRDs installed (SecretStore, ExternalSecret, ClusterSecretStore) | `kubectl get crd \| grep external-secrets.io` |

### `apps/wordpress`

| Resource | Verify with |
|---|---|
| Namespace | `kubectl get namespace wordpress` |
| PVC | `kubectl get pvc -n wordpress` — `STATUS` should be `Bound` |
| ServiceAccount + Workload Identity annotation | `kubectl describe sa wordpress-sa -n wordpress` (shown earlier — confirms `iam.gke.io/gcp-service-account: wordpress-gsa@...`) |
| Deployment / Pods | `kubectl get deployment,pods -n wordpress` |
| Service | `kubectl get svc -n wordpress` |
| Static IP reservation | `gcloud compute addresses describe wordpress-ip --global --format="get(address, status)"` — `status` should be `RESERVED` or `IN_USE` |
| Ingress (and whether it picked up the static IP) | `kubectl get ingress -n wordpress -o wide` |
| BackendConfig / FrontendConfig | `kubectl get backendconfig,frontendconfig -n wordpress` |
| ManagedCertificate | `kubectl describe managedcertificate wordpress-cert -n wordpress` — `Status.CertificateStatus` should eventually read `Active` |
| SecretStore | `kubectl get secretstore -n wordpress` and `kubectl describe secretstore <name> -n wordpress` — check `Status.Conditions` shows `Valid` |
| ExternalSecret | `kubectl get externalsecret -n wordpress` and `kubectl describe externalsecret <name> -n wordpress` — check `Status.Conditions` shows `SecretSynced` |
| The actual synced Kubernetes Secret | `kubectl get secret wordpress-db -n wordpress` (note: `kubectl describe` won't show the value, only that it exists — that's intentional) |

### `backup-job/` (applied via `kubectl`, not Terraform)

| Resource | Verify with |
|---|---|
| ServiceAccount | `kubectl get sa cloudsql-backup -n wordpress` |
| CronJob | `kubectl get cronjob -n wordpress` |
| Last run's Job/Pod logs | `kubectl get jobs -n wordpress` then `kubectl logs -n wordpress job/<job-name>` |

### A couple of broad sweeps, useful anytime

```bash
gcloud container clusters list
gcloud sql instances list
gcloud secrets list
gcloud artifacts repositories list
gcloud compute addresses list --global
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc,ingress -n wordpress
kubectl get managedcertificate -n wordpress
kubectl get externalsecret,secretstore -n wordpress
```

---

## 21. Destroy Walkthrough

Destroy in the **reverse** order of creation — `wordpress` → `external-secrets` → `infra` — otherwise you'll orphan Kubernetes objects on a cluster that no longer exists, or hit dependency errors.

```bash
cd apps/wordpress && terraform destroy
cd ../external-secrets && terraform destroy
cd ../../infra && terraform destroy
```

Or use the `terraform-infra-destroy.yml` workflow (manual, requires typing `DESTROY` in the `confirm` input) for the `infra/` layer — it runs a destroy plan first, uploads it as an artifact, then applies it.

---

## 22. Cost Estimation

Indicative monthly cost in `asia-south1` if left running 24/7 (always check the [GCP Pricing Calculator](https://cloud.google.com/products/calculator)):

| Resource | Approx. Monthly |
|---|---|
| GKE management fee | ~$74 |
| 2× `e2-small` nodes | ~$25–35 |
| Cloud NAT | ~$32 + usage |
| Cloud SQL (small tier, zonal) | ~$50–70 |
| Cloud Storage (state + backups) | ~$1–5 |
| Static IP (in use) | ~$0 (charged only if reserved but unused) |
| **Rough total** | **~$185–220/month** |

Stop/destroy resources when not actively demoing to avoid ongoing charges.

---

## 23. Security Best Practices

- ✅ Keyless CI/CD via WIF, ✅ private GKE nodes, ✅ private-IP-only Cloud SQL, ✅ least-privilege per-workload service accounts, ✅ secrets in Secret Manager (not plain Kubernetes YAML), ✅ `.gitignore` blocks state/plan/key files from ever reaching Git, ✅ WordPress now correctly uses `wordpress-gsa` (not the node SA) for its Workload Identity binding — verified live via `kubectl describe sa wordpress-sa -n wordpress`
- ⚠️ Restrict GKE `master_authorized_networks_config` (currently open) to known IP ranges
- ⚠️ Set `deletion_protection = true` on GKE and Cloud SQL before calling this "production"
- ⚠️ Consider Binary Authorization + Policy Controller for supply-chain/policy enforcement
- ⚠️ Delete the remaining inert `.yaml`/`.tf-backup` leftovers in `apps/wordpress/modules/` (Section 3 note) for a fully clean repo

---

## 24. Troubleshooting

| # | Issue | Cause | Fix |
|---|---|---|---|
| 1 | `Error: Module not found` when running `terraform init` inside plain `apps/` (historical) | Old stray `apps/*.tf` files referenced a module path that never existed — these have since been deleted | N/A now — always `cd apps/wordpress` or `cd apps/external-secrets` before running any `terraform` command |
| 2 | ~~WordPress pod can't call Secret Manager even though IAM looks correct~~ — **RESOLVED** | `apps/wordpress/main.tf` used to pass `node_service_account` (the GKE node SA) into `gcp_service_account`, not `wordpress_gsa_email` — but the Workload Identity binding in `infra/modules/iam/wordpress.tf` trusts the **wordpress-gsa**, not the node SA | Fixed: added `output "wordpress_gsa_email" { value = module.iam.wordpress_gsa_email }` to `infra/outputs.tf`, and changed `apps/wordpress/main.tf` to use `data.terraform_remote_state.infra.outputs.wordpress_gsa_email`. Confirmed with `kubectl describe sa wordpress-sa -n wordpress`. |
| 3 | `apps/wordpress` plan fails: outputs come back `null` | `infra` hasn't been applied yet, or its state prefix doesn't match what `apps/wordpress/main.tf` expects | Apply `infra` first; confirm the `bucket`/`prefix` in the `terraform_remote_state` block matches `infra/backend.tf` exactly |
| 4 | `Error: Backend configuration changed` on `terraform init` in `bootstrap/` | You renamed `backend.tf.backup` → `backend.tf` without `-migrate-state` | Run `terraform init -migrate-state` |
| 5 | Two engineers' `apply`s conflict / state lock errors | Both were applying the **same** project/prefix simultaneously | Wait for the lock to clear, or `terraform force-unlock <LOCK_ID>` if a run crashed and left a stale lock |
| 6 | `terraform state mv` used on the wrong resource, or after already applying a destroy | Address was already gone from state | Always `terraform state list` first to confirm exact addresses before `mv` |
| 7 | `ManagedCertificate` stuck in `Provisioning` for hours | DNS A record not yet pointed at the reserved static IP, or hasn't propagated | `dig yourdomain.com` to confirm it resolves to the IP from `gcloud compute addresses describe wordpress-ip --global`; Google can only issue the cert once DNS is correct |
| 8 | `ExternalSecret` shows `SecretSyncedError` | `apps/external-secrets` operator not applied yet, or applied after `apps/wordpress` | Always apply `external-secrets` before `wordpress` |
| 9 | `terraform import` succeeds but next `plan` still shows changes | The `.tf` resource block doesn't fully match the real resource's attributes yet | Adjust the `.tf` block attribute-by-attribute until `plan` shows no diff |
| 10 | `terraform apply -target=module.backup` "worked" but a later full apply shows unexpected changes elsewhere | `-target` applies only part of the dependency graph, which can leave the rest of your state slightly stale | Always follow a targeted apply with a full untargeted `plan` to confirm nothing drifted |
| 11 | GitHub Actions workflow doesn't trigger after pushing an app change | `paths:` filter in the corresponding `.yml` doesn't match your changed folder | Confirm you edited files under `apps/wordpress/**` or `apps/external-secrets/**` specifically |
| 12 | `terraform fmt -check` fails CI | Unformatted `.tf` committed | Run `terraform fmt -recursive` locally before pushing |
| 13 | `git status` shows `.terraform/` or `*.tfstate` as untracked/modified after a local run | `.gitignore` wasn't present/committed yet, or you ran Terraform before adding it | Confirm `.gitignore` is committed at the repo root; run `git rm -r --cached .terraform` once if it was accidentally committed earlier |

---

## 25. FAQ

**Q: Why 4 Terraform projects instead of folders inside one project?**
A: A "folder" inside one project still shares *one* state file and *one* lock. Separate root modules (separate `backend.tf` + `terraform init`) mean separate state, separate locks, separate blast radius — genuinely independent deployability, not just organizational tidiness.

**Q: In what order must I apply things?**
A: Always `bootstrap` → `infra` → `apps/external-secrets` → `apps/wordpress`. Each step depends on outputs or resources the previous step created.

**Q: Can `apps/wordpress` "see" everything in `infra`'s state?**
A: Only what `infra/outputs.tf` explicitly exposes. `terraform_remote_state` only exposes declared outputs, not arbitrary internal resources.

**Q: What happened to the Jenkins-VM setup and the HPA module I saw in an earlier version of this repo?**
A: Both were early experiments (a Jenkins-based CI/CD proof-of-concept, and a HorizontalPodAutoscaler module that was never wired into any pipeline). Both have been removed for a cleaner repo. HPA is listed as a [Future Improvement](#28-future-improvements) to re-add properly.

**Q: Why does `secretstore.tf` hardcode the project ID instead of using a variable?**
A: It works fine for a single-project demo, but it's not reusable as-is — parameterize it with `var.project_id` if you ever copy this module to another project.

---

## 26. Interview Questions

### A. Terraform Fundamentals

**1. What's the difference between `terraform plan` and `terraform apply`? Why should you always review a plan first?**
`plan` is a dry run — it compares your `.tf` code against the current state and prints exactly what would change (`+ create`, `~ update`, `- destroy`), without touching anything real. `apply` actually executes those changes. You review the plan first because it's your only chance to catch a mistake — like an accidental `- destroy` on a production database — before it actually happens.

**2. Explain `terraform import`. Does it write `.tf` code for you?**
`import` links an already-existing real resource (e.g. an Artifact Registry repo created by hand) to a resource address in your state file. It does **not** write `.tf` code — you have to write the matching resource block yourself first. After importing, `terraform plan` will show a diff for any attribute your `.tf` code doesn't match, so you refine the code until the plan shows no changes.

**3. Why would you use `terraform state mv` instead of just renaming a resource in `.tf` and re-applying?**
If you rename a resource in `.tf` without telling Terraform, it sees the old name as "gone" and the new name as "new," planning to destroy the old real object and create a new one — on a live GKE cluster or database, that's destructive. `state mv` tells Terraform "this is the same object, just a new address in code," with zero real-world change.

**4. What does `-target` do, and why is it discouraged as a routine habit?**
`-target=module.backup` limits `plan`/`apply` to only that resource (and its dependencies). It's useful in emergencies (e.g. you only want to fix one broken resource), but overusing it can leave your state and full configuration silently out of sync — always follow a targeted apply with a full, untargeted `plan` to confirm nothing else drifted.

**5. What is `terraform init -migrate-state` for, and when do you need it?**
It's used when you change your backend configuration (e.g. from no backend / local state to a GCS backend) and want Terraform to copy your existing state into the new location instead of starting fresh. This repo's `bootstrap/backend.tf.backup` → `backend.tf` rename is exactly this scenario — bootstrap starts with local state (the GCS bucket doesn't exist yet), then migrates to remote state once it creates that bucket.

**6. How does `terraform_remote_state` let one Terraform project read another project's outputs — and what can it NOT do?**
It's a `data` source that reads another project's state file directly from the backend (e.g. GCS) and exposes its declared `output` values as `data.terraform_remote_state.<name>.outputs.<output_name>`. It's strictly **read-only** — it cannot modify or manage resources in the other project's state, and it can only see values the other project explicitly exposed via `output {}` blocks, not arbitrary internal resources.

**7. Explain Terraform's variable precedence order.**
Highest to lowest: (1) `-var="key=value"` on the CLI, (2) `-var-file=custom.tfvars` on the CLI, (3) `*.auto.tfvars` files (auto-loaded, alphabetical), (4) `terraform.tfvars` (auto-loaded — what this repo uses), (5) `TF_VAR_key` environment variables, (6) the `default` inside the `variable {}` block. Whatever is set at the highest level wins.

**8. How does calling a module actually pass data in and out?**
A module call (`module "gke" { source = "./modules/gke" }`) passes values **in** by matching argument names to `variable {}` blocks declared inside that module folder. The module passes values **out** via its own `output {}` blocks, which the caller reads as `module.gke.<output_name>`. This is how `infra/main.tf` wires `module.network.vpc_id` straight into `module.gke`'s `vpc_id` input.

**9. Why does this repo use one GCS bucket with different `prefix` values instead of one bucket per project?**
A single bucket is simpler to create, secure (one IAM policy), and manage (one lifecycle/versioning policy), while `prefix` still gives each project (`gke/prod`, `apps/external-secrets`, `apps/wordpress`) its own fully independent state file and lock — you get isolation without multiplying buckets to manage.

**10. What happens if you `terraform apply` in `apps/wordpress` before ever applying `infra`?**
`apps/wordpress/main.tf`'s `terraform_remote_state` data source would find `infra`'s state either missing or without the outputs it expects (like `cloudsql_private_ip`). The `plan` step fails immediately with an error about a null/missing attribute — Terraform won't let you apply against values that don't exist yet.

### B. Terraform — Deeper Concepts

**11. What replaced `terraform taint`, and what does `-replace` do differently?**
`terraform taint` used to mark a resource in the state as "must be recreated on the next apply," as a separate command run before `apply`. `terraform apply -replace="<address>"` does the same thing but in a single step, directly as part of one `apply` — it's the modern, safer way (no separate state-mutating command to forget to run or accidentally leave applied).

**12. What's the purpose of `.terraform.lock.hcl`, and why commit it but not `.terraform/`?**
`.terraform.lock.hcl` records the *exact* provider versions (and their checksums) that were resolved for this configuration, so every team member and every CI run installs identical providers — reproducible builds. `.terraform/` is just the downloaded provider binaries and cached module copies themselves; they're large, environment-specific, and trivially re-downloaded by `terraform init`, so they don't belong in Git.

**13. What does `terraform validate` check that `terraform plan` doesn't?**
`validate` checks your configuration's internal syntax and logical consistency (correct HCL, referenced variables exist, types roughly match) **without contacting any provider/cloud API** — it's fast and works offline. `plan` goes further: it actually calls out to GCP to compare your code against real, current infrastructure, so it can only run with valid credentials and a reachable backend.

**14. Explain `data` vs `resource`. Where does this repo use `data` instead of a full resource?**
A `resource` block means "Terraform creates, owns, and can destroy this." A `data` block means "read information about something Terraform doesn't manage." `apps/wordpress/main.tf`'s `data "terraform_remote_state" "infra"` is a clear example — it reads `infra`'s outputs without Terraform trying to create or own that state file itself.

**15. Sensitive variable vs sensitive output — does either encrypt the value in state?**
Neither encrypts anything in the state file itself — the real value is still stored in plain text in state (which is exactly why the state bucket must be private/IAM-controlled). What `sensitive = true` does is purely a **display protection**: it stops the value from being printed in `plan`/`apply` CLI output and in the Terraform Cloud/CI logs, reducing the chance of it accidentally ending up in a build log or terminal screenshot.

**16. What is `terraform console` useful for?**
It opens an interactive REPL loaded with your current configuration and state, so you can type an expression like `module.network.vpc_id` and see its resolved value immediately — useful for testing an expression (string interpolation, a `for` expression, etc.) before committing it into an actual resource block, without running a real plan/apply cycle.

**17. Provider vs module — and why pin with `~>`?**
A **provider** (like `google`, `kubernetes`, `helm`) is a plugin that knows how to talk to a specific API and translate your `.tf` resource blocks into real API calls. A **module** is just your own reusable folder of `.tf` files — no API knowledge of its own, it only calls resources (which in turn need providers). `versions.tf` pins with `~> 6.50` (allow patch/minor upgrades within that major version) rather than an exact version, so you get bug fixes automatically but a major version bump (which can include breaking changes) still requires a deliberate decision.

**18. What does `terraform graph` produce?**
It outputs your configuration's dependency graph in DOT format, which you can pipe into Graphviz to visualize as an image. For this repo, it would visually confirm the dependency chain `network → iam → gke → cloudsql → secret-manager` (plus the independent `artifact-registry` and `backup` branches) exactly as described in Section 2's Resource Flow.

**19. `count` vs `for_each` — what happens when an item is removed from the middle of a list?**
With `count`, resources are addressed by numeric index (`resource[0]`, `resource[1]`, `resource[2]`). Removing the middle item shifts every subsequent index down by one, so Terraform sees it as "recreate almost everything after that index" — even though most of those resources didn't conceptually change. With `for_each`, resources are addressed by a stable key (usually a map key or set value), so removing one item only destroys that one resource; every other resource's address stays exactly the same, and Terraform correctly plans no change for them.

**20. Why avoid Terraform provisioners for configuration a proper resource could handle?**
Provisioners (`local-exec`, `remote-exec`) run arbitrary scripts as a side effect of resource creation — Terraform has no visibility into what they actually did, so it can't reliably detect drift, can't cleanly destroy what they set up, and their failures don't roll back cleanly. This repo's `helm_release "external_secrets"` resource is the better pattern: it's a first-class, state-tracked resource that Terraform fully understands, instead of shelling out to `helm install` via a provisioner.

**21. `terraform workspace` vs entirely separate directories/state files?**
`terraform workspace` lets one configuration maintain multiple named state files (e.g. `dev`, `prod`) that share the exact same `.tf` code. This repo instead uses fully separate directories (`bootstrap`, `infra`, `apps/external-secrets`, `apps/wordpress`) with separate `backend.tf` files — a stronger form of isolation, because each layer can have genuinely different code, different apply frequency, and a completely independent CI pipeline, not just a different state file sharing one codebase.

**22. Why does state locking on a GCS backend matter even with one CI pipeline?**
Real conflict scenarios: someone runs `terraform apply` locally on their laptop for a quick fix at the same time CI is mid-apply from a push; two different pull requests both get merged close together and their CI runs overlap; or a previous CI run hangs/times out mid-apply and a retry starts while the "stuck" one technically still holds the lock. Locking prevents any of these from writing to the same state file simultaneously and corrupting it.

### C. Variables — Extra Questions

**23. What's the difference between a `variable` and a `locals` block?**
A `variable` is an **input** — a value the caller (or a `.tfvars` file) supplies from outside the module. A `locals` block is an **internal, computed value** — something derived from other variables/resources for convenience and readability inside that same module, which the caller can never set directly.

**24. What does a `validation` block inside a `variable` do?**
It lets you enforce a rule on the input value at `plan` time, before any resource is even touched — for example, requiring `var.environment` to be one of `"dev"`, `"staging"`, `"prod"`, or requiring a CIDR string to match a certain pattern. If the rule fails, Terraform stops immediately with a clear error instead of letting a bad value flow into a resource and fail later, less clearly, deep inside a provider API call.

**25. Why give a variable a `type` at all if Terraform can often infer it?**
An explicit `type` (e.g. `type = string`, `type = list(string)`, `type = map(object({...}))`) catches mistakes early — if someone passes a list where a string was expected, Terraform errors immediately at `plan` time with a clear message, instead of the mistake surfacing confusingly later as a provider-level error.

**26. What's the difference between `default` and `required` variables?**
A `variable` with a `default` is optional — if the caller doesn't supply a value, Terraform uses the default. A `variable` with **no** `default` is required — Terraform will prompt interactively (or fail in `TF_IN_AUTOMATION`/CI mode, as this repo's workflows run with) if no value is supplied via `.tfvars`, `-var`, or `TF_VAR_`.

**27. Can a variable's default reference another variable or resource?**
No — a `default` must be a static, literal value known at parse time. It cannot reference `var.other_thing` or any resource/data attribute. If a value needs to be computed from something else, that's exactly what a `locals` block is for instead.

**28. What's the practical difference between `terraform.tfvars` and a `*.auto.tfvars` file?**
Both are auto-loaded without needing a `-var-file` flag. `terraform.tfvars` is the single conventional "main" values file (what every project in this repo uses). `*.auto.tfvars` files are useful when you want to split values across multiple files (e.g. `network.auto.tfvars`, `database.auto.tfvars`) that all get merged automatically, still without any CLI flag.

**29. Why does this repo's `.gitignore` keep `#*.tfvars` commented out instead of ignoring `.tfvars` files?**
Because this repo's `.tfvars` files only contain non-secret values (`project_id`, `region`, `cluster_name`) — genuinely useful for a new person to see committed in the repo. If a `.tfvars` file ever needed to hold something sensitive, the rule would flip: uncomment that ignore line and pass the sensitive value via `-var`, `TF_VAR_`, or a secret manager instead.

### D. Meta-Arguments

Terraform meta-arguments are special arguments that work on **any** resource or module block, regardless of resource type — they control *how Terraform manages the resource*, not the resource's own cloud-specific settings.

**30. What are Terraform's meta-arguments? Name them.**
`count`, `for_each`, `provider`, `depends_on`, and `lifecycle` (with its own sub-arguments: `create_before_destroy`, `prevent_destroy`, `ignore_changes`, `replace_triggered_by`).

**31. When would you use `depends_on` explicitly, if Terraform usually infers dependencies automatically?**
Terraform automatically infers dependency order when one resource's argument references another resource's attribute (like `module.gke` using `module.network.vpc_id`). You need an *explicit* `depends_on` only when a real-world dependency exists that isn't visible through any argument reference — this repo's `infra/main.tf` uses it exactly this way: `module.cloudsql { depends_on = [module.network] }`, because Cloud SQL's private IP depends on the private-services *peering* connection, which isn't referenced by any Cloud SQL resource argument directly.

**32. What does the `provider` meta-argument do, and when would this repo need it?**
It lets a specific resource or module use a **non-default** provider alias/configuration instead of the default one — useful when you need to manage resources in a different region, project, or account within the same configuration. `infra/modules/backup/main.tf` passes both `google` and `google-beta` explicitly via `providers = { google = google, google-beta = google-beta }` when calling that module, so it has access to beta-only resource types.

**33. Explain the `lifecycle` block's four sub-arguments.**
- `create_before_destroy = true` — build the replacement resource first, then destroy the old one (instead of the default destroy-then-create), important for something like a load balancer where you can't have zero uptime.
- `prevent_destroy = true` — Terraform refuses to destroy that resource at all, even via a full `apply`/`destroy`, until you remove this line — a safety rail worth adding to this repo's Cloud SQL instance and GKE cluster before calling it "production."
- `ignore_changes = [...]` — tells Terraform to stop reporting diffs on specific attributes that change outside Terraform's control (e.g. a GKE-managed annotation) — this repo's `apps/wordpress/modules/service.tf` uses exactly this, ignoring `metadata[0].annotations` because GKE auto-adds its own NEG-status annotations that Terraform shouldn't fight over on every plan.
- `replace_triggered_by = [...]` — forces a resource to be recreated whenever a *different*, referenced resource/attribute changes, even if nothing in this resource's own arguments changed.

**34. Why is `count` sometimes preferred over `for_each` despite the index-shifting problem mentioned in Q19?**
`count` is simpler and fine when you genuinely just need "N identical copies" and never plan to remove one from the middle (e.g. a fixed-size list of firewall rules that are always managed as a whole). `for_each` is preferred whenever items have a meaningful, stable identity (a name, an email, a namespace) — like this repo's IAM module, which conceptually creates "one service account per named workload" rather than "N generic service accounts."

### E. Platform/Architecture

**35. What problem does a Terraform "bootstrap" project solve?**
Terraform needs a remote backend to exist before it can safely manage anything as a team, but you can't create that backend's own storage bucket using state that would need to live inside that very bucket — a chicken-and-egg problem. `bootstrap/` solves it by running once with local state, creating the GCS bucket and CI identity everything else then depends on.

**36. Explain Workload Identity Federation vs a downloaded service account key.**
A downloaded JSON key is a long-lived secret — if it leaks, an attacker has standing access until someone notices and manually revokes it. WIF instead lets GitHub Actions present its own short-lived, GitHub-signed OIDC token, which GCP exchanges (only for the specific trusted repository) for a short-lived GCP access token. Nothing is stored anywhere, and there's nothing long-lived to leak or rotate.

**37. Why does a private GKE cluster still need Cloud NAT?**
"Private" means the nodes have no public IP addresses of their own. But they still need outbound internet access sometimes (pulling a public Docker image, reaching an external API). Cloud NAT provides that outbound-only path without ever giving the nodes a publicly reachable inbound address.

**38. Why is splitting IAM into per-workload service accounts better than one shared service account?**
Least privilege: if any single workload (say, the WordPress pod) is compromised, the attacker only inherits that one service account's narrow permissions (e.g. read one secret) — not the combined permissions of the entire cluster, database, and CI/CD pipeline, which is what a shared account would expose.

**39. Why store the DB password in Secret Manager instead of a plain Kubernetes Secret?**
A plain Kubernetes Secret is only base64-encoded (trivially reversible) and, if ever written into a YAML file, risks ending up committed to Git. Secret Manager stores it properly encrypted with real access control and audit logging, and External Secrets Operator only pulls it into the cluster at runtime — the password is never hand-typed or hand-copied at any point.

---

## 27. Learning Notes

- **Splitting by lifecycle, not by "logical grouping," is the real lesson here.** `bootstrap`/`infra`/`external-secrets`/`wordpress` aren't split because they're "different topics" — they're split because they change at different *frequencies* and are owned by different *people*.
- **`terraform_remote_state` is how independent projects stay in sync without copy-pasting values** — always trace a value back to which project's `outputs.tf` actually declared it.
- **A missing output is often the real bug**, not the consuming code. The `wordpress_gsa_email` gap (Section 11) was a perfect real example: the *symptom* looked like it was in `apps/wordpress/main.tf`, but the *root cause* was one missing `output` block in `infra/outputs.tf`. It's now fixed and verified live — a good example of how a one-line root-cause fix in one project (`infra`) resolves a downstream symptom in a completely separate project (`apps/wordpress`).
- **State is not a suggestion — it's the source of truth Terraform diffs against.** Every `state mv`, `import`, and backend migration exists to keep that source of truth accurate when the real world and your `.tf` code diverge for legitimate reasons (refactors, adopting existing resources, moving backends).
- **`-target`, `-replace`, and manual state surgery are last resorts, not normal workflow** — the normal workflow is: edit `.tf`, run `plan`, read it carefully, `apply`.
- **A clean repo is part of good IaC hygiene.** Removing the Jenkins-VM experiment, the unused HPA module, and the stray `apps/*.tf` files wasn't just tidying up — every dead file left behind is one more thing a future engineer (or interviewer!) has to figure out is safe to ignore.

---

## 28. Future Improvements

- [x] ~~Add the missing `wordpress_gsa_email` output to `infra/outputs.tf` and fix `apps/wordpress/main.tf` to use it~~ — done
- [ ] Re-add a proper HPA (HorizontalPodAutoscaler) as a real module under `apps/wordpress/modules/`, wired into that project's `main.tf`
- [ ] Delete the remaining inert `.yaml`/`.tf-backup` files in `apps/wordpress/modules/`
- [ ] Parameterize `secretstore.tf`'s hardcoded `projectID` with `var.project_id`
- [ ] Add a staging environment (separate `.tfvars` + separate backend `prefix` per environment, times 4 projects)
- [ ] Add Terratest/`terraform test` coverage for each of the 4 projects
- [ ] Add Prometheus/Grafana and ArgoCD as discussed previously

---

*This README documents the current, cleaned-up `gke-infra-terraform` repository — four independent Terraform projects working together as one platform.*
