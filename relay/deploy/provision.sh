#!/bin/bash
set -euo pipefail

# Prism Relay — Server Provisioning Script
# Run on a fresh Ubuntu 24.04 droplet as root.
# Usage: ./provision.sh [CLOUDFLARE_TUNNEL_TOKEN]

TUNNEL_TOKEN="${1:-}"
RELAY_DIR="/opt/prism-relay"
CRYPT_FILE="/cryptfile"
CRYPT_SIZE_MB=8192
SWAP_SIZE="2G"
MOUNT_POINT="/mnt/encrypted"

echo "=== Prism Relay Provisioning ==="

# --- System updates & packages ---
echo "[1/7] Installing system packages..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cryptsetup ufw curl

# --- Firewall ---
echo "[2/7] Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable

# --- Swap ---
echo "[3/7] Setting up ${SWAP_SIZE} swap..."
if [ ! -f /swapfile ]; then
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "  Swap created."
else
    echo "  Swap already exists, skipping."
fi

# --- LUKS encrypted storage ---
echo "[4/7] Setting up LUKS encrypted storage..."
if [ ! -f "$CRYPT_FILE" ]; then
    echo "  Allocating ${CRYPT_SIZE_MB}MB encrypted container..."
    dd if=/dev/zero of="$CRYPT_FILE" bs=1M count="$CRYPT_SIZE_MB" status=progress

    # Create tmpfs for key (RAM only)
    mkdir -p /run/keys
    mount -t tmpfs -o size=1M,noexec,nosuid tmpfs /run/keys

    # Generate random key
    dd if=/dev/urandom of=/run/keys/luks.key bs=512 count=1 2>/dev/null
    chmod 400 /run/keys/luks.key

    # Set up loop device, format, open
    LOOP=$(losetup --find --show "$CRYPT_FILE")
    cryptsetup luksFormat --batch-mode "$LOOP" /run/keys/luks.key
    cryptsetup luksOpen "$LOOP" encrypted --key-file /run/keys/luks.key

    # Create filesystem
    mkfs.ext4 /dev/mapper/encrypted
    mkdir -p "$MOUNT_POINT"
    mount /dev/mapper/encrypted "$MOUNT_POINT"
    mkdir -p "$MOUNT_POINT/relay"

    # Backup key — SAVE THIS SOMEWHERE SAFE
    echo ""
    echo "  ============================================"
    echo "  LUKS KEY (base64) — SAVE THIS IN YOUR"
    echo "  PASSWORD MANAGER. YOU NEED IT AFTER REBOOT."
    echo "  ============================================"
    base64 /run/keys/luks.key
    echo "  ============================================"
    echo ""
else
    echo "  Crypto container exists. Checking mount..."
    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "  Volume not mounted. Run /opt/unlock-relay.sh to unlock."
    else
        echo "  Already mounted."
    fi
fi

# --- Docker ---
echo "[5/7] Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    echo "  Docker installed."
else
    echo "  Docker already installed."
fi

# --- Deploy relay ---
echo "[6/7] Setting up relay..."
mkdir -p "$RELAY_DIR"

# Generate metrics token if .env doesn't exist
if [ ! -f "$RELAY_DIR/.env" ]; then
    METRICS_TOKEN=$(openssl rand -hex 32)
    cat > "$RELAY_DIR/.env" << EOF
CLOUDFLARE_TUNNEL_TOKEN=${TUNNEL_TOKEN}
METRICS_TOKEN=${METRICS_TOKEN}
RATE_LIMIT_PER_MINUTE=300
EOF
    chmod 600 "$RELAY_DIR/.env"
    echo "  Created .env (metrics token: ${METRICS_TOKEN:0:16}...)"
else
    echo "  .env already exists, preserving."
    # Update tunnel token if provided
    if [ -n "$TUNNEL_TOKEN" ]; then
        sed -i "s|^CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=${TUNNEL_TOKEN}|" "$RELAY_DIR/.env"
        echo "  Updated tunnel token."
    fi
fi

# --- Unlock/recovery script ---
echo "[7/7] Creating recovery scripts..."
cat > /opt/unlock-relay.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "=== Prism Relay Unlock ==="

# Re-attach loop device
if ! losetup -a | grep -q cryptfile; then
    LOOP=$(losetup --find --show /cryptfile)
    echo "Loop device: $LOOP"
else
    LOOP=$(losetup -a | grep cryptfile | cut -d: -f1)
    echo "Loop device already attached: $LOOP"
fi

# Mount tmpfs for key
mkdir -p /run/keys
if ! mountpoint -q /run/keys 2>/dev/null; then
    mount -t tmpfs -o size=1M,noexec,nosuid tmpfs /run/keys
fi

echo "Paste your LUKS key (base64), then press Enter + Ctrl+D:"
base64 -d > /run/keys/luks.key
chmod 400 /run/keys/luks.key

# Unlock and mount
cryptsetup luksOpen "$LOOP" encrypted --key-file /run/keys/luks.key
mount /dev/mapper/encrypted /mnt/encrypted

# Restart containers
cd /opt/prism-relay
docker compose up -d relay cloudflared node-exporter

echo "Relay is running."
docker compose ps
SCRIPT
chmod +x /opt/unlock-relay.sh

cat > /opt/lock-relay.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "=== Prism Relay Lock ==="

cd /opt/prism-relay
docker compose down

umount /mnt/encrypted
cryptsetup luksClose encrypted

LOOP=$(losetup -a | grep cryptfile | cut -d: -f1)
losetup -d "$LOOP"

# Wipe key from RAM
rm -f /run/keys/luks.key

echo "Volume locked. Data is inaccessible."
SCRIPT
chmod +x /opt/lock-relay.sh

echo ""
echo "=== Provisioning complete ==="
echo ""
echo "Next steps:"
echo "  1. Save the LUKS key above in your password manager"
echo "  2. rsync relay source (see relay/deploy/DEPLOY.md deploy command)"
echo "  3. Set CLOUDFLARE_TUNNEL_TOKEN in $RELAY_DIR/.env"
echo "  4. cd $RELAY_DIR && docker compose up -d --build"
echo ""
echo "After reboot:  ssh root@<ip> /opt/unlock-relay.sh"
echo "Manual lock:   ssh root@<ip> /opt/lock-relay.sh"
