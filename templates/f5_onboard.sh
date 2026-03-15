#!/bin/bash

LOG_FILE=/var/log/user_data_onboard.log
exec > $LOG_FILE 2>&1

set -e
trap 'echo "ERROR: Script failed at line $LINENO. Check $LOG_FILE for details."' ERR

echo "============================================"
echo "Starting BIG-IP Onboarding..."
echo "Timestamp: $(date)"
echo "============================================"

# ── 1. Wait for MCPD ────────────────────────────────────────────────────────
echo "[1/6] Waiting for MCPD to be ready..."
source /usr/lib/bigstart/bigip-ready-functions
wait_bigip_ready
echo "MCPD is ready."

# ── 2. Set Admin Password ────────────────────────────────────────────────────
echo "[2/6] Setting Admin Password..."
tmsh modify auth user admin password '${admin_pass}'
tmsh save sys config
echo "Admin password set and config saved."

# ── 3. Apply License ─────────────────────────────────────────────────────────
echo "[3/6] Applying License: ${license_key}"
LICENSE_OK=false
for i in {1..10}; do
    if tmsh install sys license registration-key ${license_key}; then
        echo "License installed successfully on attempt $i!"
        LICENSE_OK=true
        break
    else
        echo "License attempt $i/10 failed. Retrying in 30 seconds..."
        sleep 30
    fi
done

if [ "$LICENSE_OK" = false ]; then
    echo "ERROR: License installation failed after 10 attempts. Aborting."
    exit 1
fi

# Wait for MCPD to re-stabilize after licensing
echo "Waiting for MCPD to re-stabilize after licensing..."
wait_bigip_ready
echo "MCPD stable post-licensing."

# ── 4. Prepare Download Directory ───────────────────────────────────────────
echo "[4/6] Preparing download directory..."
DOWNLOAD_DIR="/var/config/rest/downloads"
cd "$DOWNLOAD_DIR"
echo "Download directory ready: $DOWNLOAD_DIR"

echo "Downloading DO package from GitHub..."
for i in {1..5}; do
    # -L follows redirects, -O saves the remote filename, --fail catches HTTP errors
    curl -k -L -O "${do_url}"
    
    if [ $? -eq 0 ]; then
        echo "DO package downloaded successfully!"
        break
    else
        echo "Attempt $i failed to download DO package. Retrying in 15 seconds..."
        sleep 15
    fi
done

# Robust Download Loop for CFE Package
echo "Downloading CFE package from GitHub..."
for i in {1..5}; do
    curl -k -L -O "${cfe_url}"
    
    if [ $? -eq 0 ]; then
        echo "CFE package downloaded successfully!"
        break
    else
        echo "Attempt $i failed to download CFE package. Retrying in 15 seconds..."
        sleep 15
    fi
done
# ── Done ─────────────────────────────────────────────────────────────────────
echo "============================================"
echo "BIG-IP Onboarding Complete!"
echo "Timestamp: $(date)"
echo "Packages ready in: $DOWNLOAD_DIR"
echo "Handing over to Terraform for package installation."
echo "============================================"