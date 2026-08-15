# Post-Mortem & Troubleshooting Audit Guide

This document captures all technical challenges, configuration gotchas, and architectural issues encountered during the implementation and deployment of this Multi-Tier Docker application onto AWS EC2, along with verification steps for future cross-checking.

---

## 🚩 Summary of Encountered Issues & Root Causes

### 1. SSH Private Key Permission Denied (`bad permissions 0555`)
- **Symptom**: `Permissions 0555 for 'incidentops-key.pem' are too open. Load key: bad permissions. Permission denied (publickey)`.
- **Root Cause**: OpenSSH enforces strict file permission checks. On Windows, inherited NTFS permissions granted read/write access to multiple user groups (`Administrators`, `SYSTEM`, `Users`), which SSH rejects.
- **Resolution**: Ran `icacls` on Windows to strip inherited permissions and restrict access exclusively to the current user (`icacls key.pem /inheritance:r /grant:r %username%:F`).
- **Future Check**: Ensure all `.pem` key files have strict single-user permissions (`chmod 400` on Linux/macOS or `icacls` inheritance removal on Windows).

---

### 2. HTTP Port 80 Connection Timeout / Unreachable Server
- **Symptom**: Browser returned `TimedOut` or connection error when accessing `http://<EC2-PUBLIC-IP>/`.
- **Root Cause**:
  1. AWS EC2 Security Group inbound rules defaulted to blocking HTTP Port 80.
  2. Stopping and restarting EC2 released the dynamic public IP address, changing the server IP.
- **Resolution**:
  1. Added Inbound Rule allowing `HTTP (Port 80)` from `0.0.0.0/0`.
  2. Recommended allocating an **AWS Elastic IP (EIP)** so the public IP remains static across instance restarts.
- **Future Check**: Verify Security Group inbound rules allow Port 80 and check if EC2 public IP changed after a reboot.

---

### 3. Dockerfile `npm ci` Failure Without `package-lock.json`
- **Symptom**: `npm error code EUSAGE: The npm ci command can only install with an existing package-lock.json`.
- **Root Cause**: Multi-stage Dockerfile used `RUN npm ci`, which strictly requires a `package-lock.json` file. Since `package-lock.json` was not committed in the initial setup, the build failed inside the container.
- **Resolution**: Updated `backend/Dockerfile` to use `RUN npm install` for initial builds.
- **Future Check**: Either commit `package-lock.json` to enable deterministic `npm ci` builds or keep `RUN npm install` in Dockerfiles.

---

### 4. Temporary Health Check Red Light on Startup
- **Symptom**: Frontend UI briefly showed red status for Backend API and Database immediately after deployment.
- **Root Cause**: PostgreSQL container takes 5–10 seconds to run initial database setup and report `healthy`. During this initialization window, Express API queries to Postgres failed temporarily.
- **Resolution**: Docker Compose handles container dependencies via `depends_on: { postgres: { condition: service_healthy } }`. The UI auto-recovers to Green once Postgres passes health checks.
- **Future Check**: Always allow 10–15 seconds post-deployment for container health probes to complete before checking UI status.

---

### 5. `awscli` Package Missing in Ubuntu 24.04 Repositories
- **Symptom**: `E: Package 'awscli' has no installation candidate` when running `deploy-ec2.sh`.
- **Root Cause**: Ubuntu 24.04 (Noble Numbat) changed package names and deprecated `awscli` in favor of `awscli-2` or snap distribution.
- **Resolution**: Updated `deploy-ec2.sh` to gracefully fallback (`sudo apt-get install -y ... || true`) and handle AWS CLI checks dynamically.
- **Future Check**: On Ubuntu 24.04+, use AWS CLI v2 installation script or Snap package if `awscli` APT package is missing.

---

### 6. Git Pre-Commit Hook Secret Detection
- **Symptom**: `COMMIT BLOCKED: Hardcoded password or secret assignment detected in staged changes`.
- **Root Cause**: Local Git `pre-commit` hook detected a fallback hardcoded password string in shell scripts.
- **Resolution**: Removed hardcoded fallback strings to comply with the zero-trust secret policy.
- **Future Check**: Secrets must never be written into code; use environment variables or AWS SSM Parameter Store (`/prod/ecommerce/db_password`).

---

## 📋 Pre-Flight Checklist for Future Deployments

- [ ] **AWS Parameter Store**: Parameter `/prod/ecommerce/db_password` exists in SSM.
- [ ] **EC2 IAM Role**: EC2 instance has an IAM Role attached with `AmazonSSMReadOnlyAccess`.
- [ ] **Security Group**: Inbound rules allow **Port 80 (HTTP)** and **Port 22 (SSH)**.
- [ ] **SSH Key Permissions**: `.pem` key has strict permissions (`chmod 400` or `icacls` restricted).
- [ ] **GitHub Secrets**: `EC2_HOST`, `EC2_USERNAME`, and `EC2_SSH_KEY` are configured in GitHub repository settings.
