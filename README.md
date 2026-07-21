# GKE Production Infrastructure on Google Cloud using Terraform

## Overview

This project provisions a production-ready Kubernetes platform on Google Cloud Platform using Terraform.

The infrastructure is fully automated and includes networking, GKE, Cloud SQL, Secret Manager, External Secrets, Artifact Registry, automated backups, GitHub Actions CI/CD, and Workload Identity.

The goal of this repository is to demonstrate how a real production platform can be built using Infrastructure as Code.

---

# Architecture

```
GitHub
      │
      ▼
GitHub Actions (OIDC Authentication)
      │
      ▼
Terraform
      │
      ├───────────────┐
      ▼               ▼
     VPC           Artifact Registry
      │
      ▼
     GKE Cluster
      │
      ├─────────────┐
      ▼             ▼
 WordPress      External Secrets
      │             │
      ▼             ▼
 Persistent     Secret Manager
 Volume
      │
      ▼
 Cloud SQL (Private IP)

      │
      ▼
Backup Job
      │
      ▼
Cloud Storage
```

---

# Features

- Terraform Infrastructure as Code
- Google Kubernetes Engine
- Private Cloud SQL
- Secret Manager
- External Secrets Operator
- Artifact Registry
- Workload Identity
- Automated Cloud SQL Backup
- WordPress Upload Backup
- GitHub Actions CI/CD
- Production Module Structure

---

# Repository Structure

```
bootstrap/
modules/
backup-job/
.github/workflows/
scripts/
docs/
```

---

# Modules

## Network

Creates

- VPC
- Private Subnet
- Secondary Ranges
- Cloud Router
- Cloud NAT

---

## GKE

Creates

- Private Cluster
- Node Pool
- Workload Identity
- Logging
- Monitoring

---

## IAM

Creates

- Terraform Service Account
- Node Service Account
- Backup Service Account
- Required IAM Bindings

---

## Cloud SQL

Creates

- MySQL Instance
- Private IP
- Database
- User

---

## Secret Manager

Stores

- WordPress Database Password

---

## External Secrets

Synchronizes

Google Secret Manager

↓

Kubernetes Secret

---

## WordPress

Deploys

- PVC
- Deployment
- Service
- Ingress

---

## Backup

Performs

- Cloud SQL Export
- Uploads Backup
- Metadata Generation
- Restore Support

---

# Deployment Flow

Bootstrap

↓

Terraform Init

↓

Terraform Apply

↓

Build Backup Image

↓

Push Docker Image

↓

Deploy Backup CronJob

↓

Deploy WordPress

---

# Backup Flow

CronJob

↓

Cloud SQL Export

↓

Upload SQL

↓

Compress Uploads

↓

Upload Archive

↓

Generate Manifest

↓

Store Metadata

---

# Restore Flow

Download Latest Backup

↓

Import SQL

↓

Download Uploads

↓

Extract Uploads

↓

Restart WordPress

↓

Validate

---

# Technologies Used

- Terraform
- Google Cloud Platform
- GKE
- Cloud SQL
- Artifact Registry
- Secret Manager
- GitHub Actions
- Docker
- Kubernetes

---

# Current Status

| Component | Status |
|------------|--------|
| Network | ✅ |
| GKE | ✅ |
| Cloud SQL | ✅ |
| Secret Manager | ✅ |
| External Secrets | ✅ |
| Backup | ✅ |
| Restore | 🚧 |
| Monitoring | 🚧 |
| Documentation | 🚧 |

---

# Future Enhancements

- Prometheus
- Grafana
- ArgoCD
- Velero
- Binary Authorization
- Policy Controller
