# Jenkins CI/CD Pipeline for Terraform on Google Cloud Platform (GCP)

![Cloud](https://img.shields.io/badge/Cloud-Google%20Cloud-4285F4?logo=googlecloud&logoColor=white)
![CI/CD](https://img.shields.io/badge/CI%2FCD-Jenkins-D24939?logo=jenkins&logoColor=white)
![IaC](https://img.shields.io/badge/IaC-Terraform-844FBA?logo=terraform&logoColor=white)
![Auth](https://img.shields.io/badge/Auth-ADC%20(keyless)-success)

Automate Google Cloud infrastructure provisioning with **Jenkins**, **Terraform**, and **GCP**.

Jenkins runs on a Google Compute Engine (GCE) VM and executes Terraform through a parameterized pipeline. Users choose **`apply`** to create or update infrastructure, or **`destroy`** to remove it.

> 🔐 **Security highlight:** Terraform authenticates using the GCE VM's attached service account via **Application Default Credentials (ADC)**. No service account JSON keys are ever downloaded, stored, or rotated.

---

## Table of Contents

- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Prerequisites](#prerequisites)
- [Setup Guide](#setup-guide)
- [Repository Structure](#repository-structure)
- [Example Configuration](#example-configuration)
- [Jenkinsfile](#jenkinsfile)
- [Running the Pipeline](#running-the-pipeline)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [References](#references)

---

## Architecture

```
Developer
   │  git push
   ▼
GitHub Repository
   │
   ▼
Jenkins Pipeline (on GCE VM)
   ├── Checkout Source Code
   ├── Terraform Init
   ├── Terraform Validate
   ├── Terraform Plan        (apply only)
   ├── Approval Gate         (destroy only)
   └── Terraform Apply / Destroy
   │
   │  ADC via GCE metadata server (no JSON keys)
   ▼
Google Cloud Platform
   ├── Compute Engine
   ├── VPC / Networking
   └── Other Terraform-managed resources
```

## Technology Stack

| Layer | Tool |
|---|---|
| Cloud platform | Google Cloud Platform (GCP) |
| Compute | Google Compute Engine (GCE) |
| CI/CD | Jenkins |
| Infrastructure as Code | Terraform |
| Version control | Git & GitHub |
| Authentication | Attached GCP service account + Application Default Credentials (ADC) |
| Visualization | Pipeline Graph View & Pipeline Stage View |

## Prerequisites

- A Google Cloud project with **billing enabled**
- A GCE VM running **Debian or Ubuntu**
- **Jenkins** and **Terraform** installed on the VM
- A GitHub repository containing your Terraform code and `Jenkinsfile`
- A **dedicated service account** attached to the VM with least-privilege IAM roles
- A GCS bucket for remote Terraform state (recommended, see [Security Best Practices](#security-best-practices))

---

## Setup Guide

### Step 1: Create a Google Compute Engine VM

1. In the Google Cloud Console, go to **Compute Engine → VM instances**.
2. Create a VM running Debian or Ubuntu.
3. Attach a **dedicated service account** with only the IAM roles your Terraform configuration needs. Avoid `Owner` and `Editor`.
4. Set the VM's **access scopes** to *Allow full access to all Cloud APIs* (`cloud-platform`). IAM roles then control what the account can actually do.
5. Restrict firewall rules and connect over SSH.

### Step 2: Install Jenkins

Follow the official [Jenkins installation guide](https://www.jenkins.io/doc/book/installing/linux/) for your OS, then verify:

```bash
sudo systemctl status jenkins
```

Open Jenkins at `http://<VM_EXTERNAL_IP>:8080`.

> ⚠️ Restrict port `8080` to trusted IPs, or use an IAP / SSH tunnel. Do not expose Jenkins to the open internet.

### Step 3: Install Terraform

Install from HashiCorp's official APT repository:

```bash
sudo apt-get update && sudo apt-get install -y curl gnupg lsb-release

sudo install -m 0755 -d /usr/share/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
sudo chmod 644 /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update && sudo apt-get install -y terraform
```

Verify:

```bash
terraform -version
which terraform   # e.g. /usr/bin/terraform
```

### Step 4: Install Jenkins Plugins

Go to **Manage Jenkins → Plugins → Available plugins** and install:

- **Pipeline**
- **Git**
- **Pipeline Stage View** and **Pipeline Graph View** (recommended; Blue Ocean is deprecated)
- **Terraform** *(optional; not needed when calling Terraform through `sh`)*

### Step 5: Verify Google Cloud Authentication

Confirm the VM has an attached service account and that the metadata server is reachable:

```bash
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
```

You should see the service account's email address.

> **Do not** set `GOOGLE_APPLICATION_CREDENTIALS` to a JSON key file. Terraform's Google provider picks up ADC from the metadata server automatically.

---

## Repository Structure

```
terraform-gcp-jenkins/
├── main.tf          # Resources
├── variables.tf     # Input variables
├── outputs.tf       # Output values
├── providers.tf     # Provider configuration
├── versions.tf      # Terraform and provider version constraints
├── backend.tf       # Remote state (GCS)
├── .gitignore
├── Jenkinsfile
└── README.md
```

## Example Configuration

### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
```

### `providers.tf`

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
}
```

### `variables.tf`

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "asia-south1"
}
```

### `backend.tf` (recommended)

```hcl
terraform {
  backend "gcs" {
    bucket = "your-tf-state-bucket"
    prefix = "terraform/state"
  }
}
```

Create the bucket with versioning enabled:

```bash
gcloud storage buckets create gs://your-tf-state-bucket \
  --location=asia-south1 --uniform-bucket-level-access
gcloud storage buckets update gs://your-tf-state-bucket --versioning
```

### `.gitignore`

```gitignore
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
tfplan
crash.log
*.tfvars
*.json
```

> Commit `.terraform.lock.hcl` so provider versions stay consistent across builds.

---

## Jenkinsfile

The pipeline exposes an `ACTION` parameter to choose between `apply` and `destroy`. Destroy requires a manual approval before it runs.

```groovy
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()   // prevents state lock conflicts
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['apply', 'destroy'],
            description: 'Choose whether to provision or destroy infrastructure'
        )
    }

    environment {
        TF_IN_AUTOMATION = 'true'
        TF_INPUT         = '0'
        TF_VAR_project_id = 'your-gcp-project-id'
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git'
            }
        }

        stage('Terraform Version') {
            steps {
                sh 'terraform -version'
            }
        }

        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }

        stage('Terraform Validate') {
            steps {
                sh 'terraform validate'
            }
        }

        stage('Terraform Plan') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                sh 'terraform plan -out=tfplan'
            }
        }

        stage('Terraform Apply') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                sh 'terraform apply -auto-approve tfplan'
            }
        }

        stage('Approve Destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                sh 'terraform plan -destroy -out=destroy.tfplan'
                input message: 'Review the destroy plan above. Proceed?', ok: 'Destroy'
            }
        }

        stage('Terraform Destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                sh 'terraform apply -auto-approve destroy.tfplan'
            }
        }
    }

    post {
        success { echo 'Terraform pipeline completed successfully.' }
        failure { echo 'Terraform pipeline failed. Review the build logs.' }
        always  { cleanWs() }
    }
}
```

> `TF_VAR_project_id` supplies the required `project_id` variable. Without it, Terraform would wait for input and the build would fail.

---

## Running the Pipeline

1. In Jenkins, create a new **Pipeline** job.
2. Under **Pipeline**, choose *Pipeline script from SCM*, select Git, and enter your repository URL and branch.
3. Click **Build with Parameters** and select `apply` or `destroy`.
4. Watch progress in **Pipeline Graph View**.
5. For `destroy`, review the plan output and approve when prompted.

---

## Security Best Practices

| Practice | Why it matters |
|---|---|
| **Least privilege** | Grant the VM service account only the roles your resources need. |
| **Remote state in GCS** | Enables locking and shared state. Enable bucket versioning for recovery. |
| **No secrets in Git** | Never commit keys, passwords, `.tfvars` with sensitive data, or state files. |
| **Approval gates** | Require manual approval before `apply` and `destroy` in production. |
| **Restrict Jenkins access** | Limit port 8080 to trusted IPs or IAP, and enable authentication and RBAC. |
| **Separate environments** | Use separate projects, state prefixes, and service accounts for dev, staging, and prod. |
| **Pin versions** | Pin Terraform and provider versions, and commit `.terraform.lock.hcl`. |

---

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `terraform: command not found` | Jenkins can't see the binary. Confirm `which terraform` and that `/usr/bin` is in the Jenkins `PATH`. |
| `could not find default credentials` | The VM has no service account attached, or the metadata server is unreachable. Re-run the Step 5 check. |
| `403 insufficient authentication scopes` | VM access scopes are too narrow. Set the scope to `cloud-platform` (VM must be stopped to change it). |
| `403 permission denied` on a resource | The service account lacks the required IAM role. Add the specific role. |
| `Error acquiring the state lock` | Another run is active or a previous run crashed. Wait, or run `terraform force-unlock <ID>` if you're sure. |
| Build hangs at a prompt | A variable is missing a value. Set `TF_VAR_*` or pass `-var` and keep `TF_INPUT=0`. |

---

## Cleanup

To avoid ongoing charges, run the pipeline with `ACTION = destroy`. Then delete the Jenkins VM and the state bucket if they're no longer needed.

---

## References

- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform GCS Backend](https://developer.hashicorp.com/terraform/language/backend/gcs)
- [Google Cloud Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials)

---
