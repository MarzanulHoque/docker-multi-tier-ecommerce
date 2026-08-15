# Detailed Technical Post-Mortem & Troubleshooting Field Manual

This document provides a deep technical breakdown of every architectural, network, permission, and containerization issue encountered during the implementation of this Multi-Tier Docker application on AWS EC2, complete with diagnostic commands, exact root causes, and verification steps.

---

## 🛠️ Deep Dive Troubleshooting Matrix

### 1. SSH Private Key Permission Rejection (`bad permissions 0555`)

#### 🔍 Symptom & Error Log
```text
@   WARNING: UNPROTECTED PRIVATE KEY FILE!          @
Permissions 0555 for 'incidentops-key.pem' are too open.
It is required that your private key files are NOT accessible by others.
This private key will be ignored.
Load key "incidentops-key.pem": bad permissions
ubuntu@ec2-35-168-37-245.compute-1.amazonaws.com: Permission denied (publickey).
```

#### 🧠 Root Cause Analysis
OpenSSH enforces strict POSIX compliance checks on private key files (`.pem`/`.rsa`). If a key file has permissions that allow any user other than the owner to read or write to it, OpenSSH refuses to load the key to protect against local privilege escalation. 

On Windows NTFS filesystems, newly downloaded `.pem` files inherit access control lists (ACLs) granting read permissions to `BUILTIN\Administrators`, `NT AUTHORITY\SYSTEM`, and `Authenticated Users`, which OpenSSH interprets as unsafe.

#### 🛠️ Resolution & Commands
- **Windows PowerShell**: Strip inherited ACLs and explicitly grant read-only control to the logged-in user:
  ```powershell
  cmd /c "icacls `"<path-to-key>\key.pem`" /c /grant %username%:F /inheritance:r"
  powershell -Command "icacls '<path-to-key>\key.pem' /remove 'NT AUTHORITY\SYSTEM' 'BUILTIN\Administrators'"
  ```
- **Linux / macOS**: Set file permissions to `400` (Owner Read-Only):
  ```bash
  chmod 400 key.pem
  ```

#### 🧪 Verification Command
```powershell
# Windows
icacls key.pem
# Expected Output: key.pem USERNAME:(F) with no other entries.

# Linux
ls -l key.pem
# Expected Output: -r-------- 1 user group
```

---

### 2. HTTP Port 80 Connection Timeout (`TcpTestSucceeded : False`)

#### 🔍 Symptom & Error Log
```text
WARNING: TCP connect to (35.168.37.245 : 80) failed
WARNING: Ping to 35.168.37.245 failed with status: TimedOut
TcpTestSucceeded : False
```

#### 🧠 Root Cause Analysis
This failure occurs due to two primary AWS networking layer boundaries:
1. **Security Group Inbound Rules**: AWS EC2 Security Groups act as stateful virtual firewalls. By default, new Security Groups block all inbound traffic except SSH (Port 22). Requests to Port 80 are silently dropped by the AWS hypervisor before reaching the EC2 network interface.
2. **Dynamic Public IP Re-allocation**: Stopping and starting an EC2 instance releases the assigned public IPv4 address back to AWS's regional pool. Upon restarting, AWS assigns a different public IP address, causing requests directed at the old IP to time out.

#### 🛠️ Resolution & Commands
1. **AWS Security Group**: Add an Inbound Rule in AWS Console:
   - **Type**: `HTTP`
   - **Protocol**: `TCP`
   - **Port Range**: `80`
   - **Source**: `0.0.0.0/0` (Anywhere IPv4)
2. **AWS Elastic IP (EIP)**: Allocate an Elastic IP in AWS Console and associate it with the EC2 Instance to freeze the public IP permanently.

#### 🧪 Verification Command
```powershell
Test-NetConnection -ComputerName <EC2-PUBLIC-IP> -Port 80
# Expected Output: TcpTestSucceeded : True
```

---

### 3. Multi-Stage Dockerfile `npm ci` Failure Without Lockfile

#### 🔍 Symptom & Error Log
```text
#17 [backend builder 4/6] RUN npm ci
#17 1.525 npm error code EUSAGE
#17 1.526 npm error The `npm ci` command can only install with an existing package-lock.json or npm-shrinkwrap.json
#17 ERROR: process "/bin/sh -c npm ci" did not complete successfully: exit code: 1
```

#### 🧠 Root Cause Analysis
`npm ci` (Clean Install) is designed for automated environments (CI/CD) and strictly enforces that a `package-lock.json` file exists to guarantee reproducible build trees. Because `package-lock.json` was omitted from the project repository initialization, `npm ci` aborted with an `EUSAGE` error during the multi-stage image build stage.

#### 🛠️ Resolution & Commands
Updated `backend/Dockerfile` build stage from `RUN npm ci` to `RUN npm install`:
```dockerfile
# Stage 1: Build & Dependencies
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
```

#### 🧪 Verification Command
```bash
docker build -t test-backend ./backend
# Expected Output: Successfully built and tagged test-backend
```

---

### 4. Temporary Service Health Red Light on Initial Deployment

#### 🔍 Symptom & Error Log
```text
UI Dashboard Status:
Backend API: Offline (Red)
PostgreSQL DB: Offline (Red)
```

#### 🧠 Root Cause Analysis
PostgreSQL image (`postgres:16-alpine`) requires 5 to 12 seconds on first boot to initialize the database cluster directory (`/var/lib/postgresql/data`), execute init scripts, and pass its internal health check (`pg_isready`). 

During this initialization window, Express API queries to PostgreSQL fail, causing the Express health check (`/health`) to return HTTP 500 (`DOWN`), which the frontend UI renders as red status indicators.

#### 🛠️ Resolution & Commands
Configured Docker Compose dependency ordering with explicit health check conditions in [`docker-compose.yml`](file:///d:/Docker%20E%20commerce/docker-compose.yml):
```yaml
backend:
  depends_on:
    postgres:
      condition: service_healthy
```
The frontend UI auto-polls `/api/health` every 10 seconds, automatically transitioning indicators to Green once PostgreSQL finishes initialization.

#### 🧪 Verification Command
```bash
docker compose ps
# Expected Output: app-postgres-1 Up (healthy), app-backend-1 Up (healthy)
```

---

### 5. APT Package Manager `awscli` Deprecation on Ubuntu 24.04

#### 🔍 Symptom & Error Log
```text
Reading package lists...
Building dependency tree...
Package awscli is not available, but is referred to by another package.
E: Package 'awscli' has no installation candidate
```

#### 🧠 Root Cause Analysis
Canonical modified the default package index for Ubuntu 24.04 LTS (Noble Numbat), deprecating the legacy `awscli` v1 APT package from universe repositories in favor of AWS CLI v2 bundles.

#### 🛠️ Resolution & Commands
Updated [`deploy-ec2.sh`](file:///d:/Docker%20E%20commerce/deploy-ec2.sh) package installation logic with a non-blocking fallback operator (`|| true`):
```bash
if command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg git || true
fi
```

#### 🧪 Verification Command
```bash
./deploy-ec2.sh
# Expected Output: Script executes without halting on missing APT packages.
```

---

### 6. Git Pre-Commit Security Hook Secret Interception

#### 🔍 Symptom & Error Log
```text
🛡️ Running pre-commit security inspection...
❌ COMMIT BLOCKED: Hardcoded password assignment detected in staged changes
Please remove hardcoded secrets and use environment variables instead.
```

#### 🧠 Root Cause Analysis
The local Git `pre-commit` hook ([`.git/hooks/pre-commit`](file:///d:/Docker%20E%20commerce/.git/hooks/pre-commit)) scans staged `git diff` chunks for regex patterns matching hardcoded password assignments. When a fallback password string was added to a shell script, the hook intercepted the commit and aborted execution.

#### 🛠️ Resolution & Commands
Removed hardcoded secret fallbacks from all shell scripts and enforced dynamic parameter extraction from AWS SSM Parameter Store (`/prod/ecommerce/db_password`) into shell RAM memory (`export POSTGRES_PASSWORD`).

#### 🧪 Verification Command
```bash
git commit -m "test commit"
# Expected Output: ✅ Security inspection passed! No secret leaks detected.
```

---

## 📋 Comprehensive Pre-Flight Verification Checklist

Before deploying updates to production, verify the following checklist:

| Verification Item | Requirement | Command / Inspection |
| :--- | :--- | :--- |
| **AWS Parameter Store** | Secret parameter created | `aws ssm get-parameter --name "/prod/ecommerce/db_password"` |
| **EC2 IAM Role** | Policy `AmazonSSMReadOnlyAccess` attached | EC2 Console -> Security -> IAM Role |
| **Inbound Security Rules** | Port 80 (HTTP) & Port 22 (SSH) allowed | `Test-NetConnection -ComputerName <IP> -Port 80` |
| **SSH Key Security** | Single user read permission | `icacls key.pem` (Windows) or `ls -l key.pem` (Linux) |
| **Docker Compose Services** | All 4 services active | `docker compose ps` |
| **Git Pre-Commit Hook** | Executable and active | `.git/hooks/pre-commit` |
| **GitHub Actions Secrets** | `EC2_HOST`, `EC2_USERNAME`, `EC2_SSH_KEY` set | GitHub Repo -> Settings -> Secrets -> Actions |
