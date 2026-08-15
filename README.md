# Multi-Tier Containerized E-Commerce Application

A production-grade, highly available, multi-tier e-commerce web application platform deployed on **AWS EC2** using **Docker**, **Docker Compose**, **Nginx Reverse Proxy**, **Node.js/Express REST API**, and **PostgreSQL**.

---

## 👥 Repository Owner & Core Contributors

| Role | Name | GitHub | Contact |
| :--- | :--- | :--- | :--- |
| **Repository Owner & Lead Architect** | **S. M. MARZANUL HOQUE** | [@MarzanulHoque](https://github.com/MarzanulHoque) | `marzanul.haque@bizzntek.com` |

---

## 🏗️ Architecture Overview

The system implements a decoupled micro-architecture consisting of 4 isolated containerized services connected via an internal bridge network (`app-network`):

```
                        +----------------------------+
                        |     Internet Clients       |
                        +----------------------------+
                                      |
                                  [Port 80]
                                      v
                        +----------------------------+
                        |   Nginx Reverse Proxy      |
                        |       (Port 80:80)         |
                        +----------------------------+
                                  /        \
                    /-------------          -------------\
                   /                                      \
                  v                                        v
  +-------------------------------+        +-------------------------------+
  |   Frontend SPA Container      |        |     Backend API Service       |
  |     (Static Assets/UI)        |        |   (Node.js / Express REST)    |
  +-------------------------------+        +-------------------------------+
                                                           |
                                                   (Internal Port 5432)
                                                           v
                                           +-------------------------------+
                                           |     PostgreSQL Database       |
                                           |   (Healthchecked Service)     |
                                           +-------------------------------+
                                                           |
                                                   [Persistent Volume]
                                                       (pg_data)
```

---

## 🛠️ Key Technical Stack & Features

- **Reverse Proxy**: Nginx Alpine (`nginx:alpine`) as entry point routing client traffic to services.
- **Frontend Service**: Single Page Application built and published to **GitHub Container Registry (GHCR)**.
- **Backend Service**: Multi-stage Node.js REST API with automated database health-check awareness (`service_healthy` constraint).
- **Database Layer**: PostgreSQL 16 Alpine (`postgres:16-alpine`) backed by a persistent named Docker volume (`pg_data`).
- **Production Secrets Security**: Zero hardcoded credentials. Dynamic memory ingestion from **AWS Systems Manager (SSM) Parameter Store** (`/prod/ecommerce/db_password`).
- **CI/CD & Pre-commit Safety**: Integrated pre-commit security interception to prevent credential leaks into Git.

---

## 🚀 Quick Start Guide

### Prerequisites
- [Docker Engine](https://docs.docker.com/engine/install/) (v20.10+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2.0+)
- Git

### 1. Clone Repository
```bash
git clone https://github.com/MarzanulHoque/docker-multi-tier-ecommerce.git
cd docker-multi-tier-ecommerce
```

### 2. Local Environment Setup
Optionally set a custom database password using a `.env` file in the root directory:
```ini
POSTGRES_PASSWORD=your_secure_password_here
```
*(If omitted, deployment scripts and AWS parameter store will automatically handle password retrieval).*

### 3. Launch Application Stack
```bash
docker compose up -d --build
```

### 4. Verify Active Containers
```bash
docker compose ps
```

Access the application in your web browser at `http://localhost`.

---

## ☁️ AWS EC2 Automated Production Deployment

The project includes an idempotent deployment script (`deploy-ec2.sh`) configured for AWS EC2 instances:

```bash
chmod +x deploy-ec2.sh
./deploy-ec2.sh
```

**Key Deployment Features:**
1. **Idempotent Installation**: Automatically installs Docker Engine if missing, or skips dependency steps if already present.
2. **Metadata Auto-Detection**: Uses EC2 IMDSv2 to auto-detect instance AWS region (`http://169.254.169.254/latest/api/token`).
3. **SSM Secret Retrieval**: Securely fetches `POSTGRES_PASSWORD` into host memory without storing secrets on disk.

---

## 📑 Technical Documentation & Troubleshooting

For a deep-dive breakdown of resolved architectural bugs, SSH key permission fixes (`icacls`/`chmod 400`), AWS Security Group port configurations, and pre-flight verification checklists, please consult:

👉 **[Detailed Technical Post-Mortem & Field Manual](file:///d:/Docker%20E%20commerce/Project%20Files/TROUBLESHOOTING.md)**
