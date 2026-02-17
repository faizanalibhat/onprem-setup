# 🚀 Snapsec On-Premises Deployment

Welcome to the Snapsec On-Premises setup guide. This repository contains all the necessary configurations and the utility script to deploy and manage the Snapsec suite on your own infrastructure.

---

## 📋 Prerequisites

Before you begin, ensure your system meets the following requirements:

*   **Operating System:** Linux (Ubuntu, CentOS, Arch, etc.)
*   **System Tools:** `sudo` access, `curl` or `wget`
*   **Hardware (Recommended):**
    *   CPU: 4+ Cores
    *   RAM: 8GB+
    *   Storage: 50GB+ SSD

---

## 🛠️ Getting Started

We provide a specialized `setup.sh` utility to automate the installation, configuration, and maintenance of your instance.

### 1. Clone the Repository
```bash
git clone https://github.com/faizanalibhat/onprem-setup.git
cd onprem-setup
```

### 2. Run the Installer
```bash
./setup.sh install
```

### 3. During Installation
The interactive script will guide you through:
- **Dependency Check:** Verifying and automatically installing `docker`, `docker-compose`, `openssl`, and `cron`.
- **Environment Setup:** 
    - You will be prompted for the **Base URL** (e.g., `https://suite.snapsec.co`).
    - The script will automatically generate secure `ENCRYPTION_KEY` and `SERVICE_KEY`.
- **Registry Authentication:** 
    - You will need to provide your **GitHub Pull-Only Token** to access the private container registry (`ghcr.io`).
    - *Tip: This token will be securely cached in `.suite-auth/` for future updates.*
- **Maintenance Setup:** 
    - A system cron job will be scheduled to keep your instance updated every Sunday at midnight.

---

## 🔄 Managing the Application

### Update Manually
To pull the latest images and restart services without waiting for the weekly cron job:
```bash
./setup.sh update
```

### Monitoring Logs
To check the status of your services and view real-time logs:
```bash
docker-compose ps
docker-compose logs -f
```

### Troubleshooting Authentication
If your registry token expires or needs to be changed, simply run:
```bash
rm -rf .suite-auth/
./setup.sh install
```
The script will detect the missing credentials and prompt you for a new token.

---

## ⚙️ Configuration File (`.env`)

While the script handles most configurations, you can manually tune settings in the `.env` file:

| Variable | Description |
| :--- | :--- |
| `BASE_URL` | The public-facing URL of your instance. |
| `ENABLE_TELEMETRY` | Set to `true` or `false` to toggle anonymous health reporting. |
| `MONGODB_PASS` | Password for the internal database. |
| `REDIS_PASS` | Password for the internal cache. |

---

## 🛡️ Security Best Practices

1.  **Restrict Access:** Ensure port `80` (or `443` if using a proxy) is only accessible from your authorized networks.
2.  **External Proxy:** We recommend running a reverse proxy like Nginx or Traefik with SSL termination in front of the application.
3.  **Token Rotation:** Rotate your GitHub Pull-Only Token every 90 days to maintain security.

---

Developed with ❤️ by the **Snapsec Team**.
