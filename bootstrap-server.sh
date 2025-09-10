#!/usr/bin/env bash
# bootstrap-server.sh
# Initial Linux server hardening & setup (Debian/Ubuntu, RHEL/AlmaLinux/Rocky, Fedora)
# Usage:
#   sudo ./bootstrap-server.sh \
#     --username devops \
#     --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexampleyourpubkey user@host" \
#     --ufw-ports "22,80,443" \
#     --timezone "Europe/Warsaw" \
#     --no-password-login

set -euo pipefail

# ---------- Defaults ----------
USERNAME=""
SSH_KEY=""
UFW_PORTS="22"
TIMEZONE="UTC"
DISABLE_PW_LOGIN=false

# ---------- Helpers ----------
log() { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err() { echo -e "\033[1;31m[-] $*\033[0m" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------- Parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --ufw-ports) UFW_PORTS="$2"; shift 2 ;;
    --timezone) TIMEZONE="$2"; shift 2 ;;
    --no-password-login) DISABLE_PW_LOGIN=true; shift ;;
    -h|--help)
      cat <<EOF
Usage: sudo $0 [options]
  --username NAME            Create a non-root sudo user
  --ssh-key "KEY"            Authorized SSH public key for that user
  --ufw-ports "22,80,443"    Comma-separated allowed ports
  --timezone "Region/City"   Set system timezone (default: UTC)
  --no-password-login        Disable SSH password authentication
EOF
      exit 0
      ;;
    *) err "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  err "Run as root or with sudo."
  exit 1
fi

# ---------- Detect distro & pkg mgr ----------
ID="$(. /etc/os-release; echo "${ID:-unknown}")"
ID_LIKE="$(. /etc/os-release; echo "${ID_LIKE:-}")"
PKG=""
if has_cmd apt-get; then PKG="apt";
elif has_cmd dnf; then PKG="dnf";
elif has_cmd yum; then PKG="yum";
else err "Unsupported package manager."; exit 1; fi

log "Detected distro: ${ID} (pkg manager: ${PKG})"

# ---------- Set timezone ----------
if [[ -n "$TIMEZONE" ]]; then
  if has_cmd timedatectl; then
    timedatectl set-timezone "$TIMEZONE" || warn "Failed to set timezone"
  else
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime || warn "Failed to symlink timezone"
  fi
  log "Timezone set to $TIMEZONE"
fi

# ---------- Update system & install base tools ----------
case "$PKG" in
  apt)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y \
      curl wget git vim htop ufw fail2ban unzip ca-certificates gnupg lsb-release net-tools
    ;;
  dnf|yum)
    $PKG -y update
    $PKG -y install \
      curl wget git vim htop firewalld fail2ban unzip ca-certificates gnupg2 net-tools
    systemctl enable --now firewalld || warn "firewalld enable failed"
    ;;
esac
log "Base tools installed."

# ---------- Create user & sudo ----------
if [[ -n "$USERNAME" ]]; then
  if id "$USERNAME" &>/dev/null; then
    log "User '$USERNAME' already exists."
  else
    useradd -m -s /bin/bash "$USERNAME"
    log "Created user '$USERNAME'."
  fi

  # Add to sudo/wheel
  if getent group sudo >/dev/null; then
    usermod -aG sudo "$USERNAME"
  elif getent group wheel >/dev/null; then
    usermod -aG wheel "$USERNAME"
  fi
  log "Granted sudo privileges to '$USERNAME'."

  # SSH key setup
  if [[ -n "$SSH_KEY" ]]; then
    HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
    mkdir -p "$HOME_DIR/.ssh"
    echo "$SSH_KEY" > "$HOME_DIR/.ssh/authorized_keys"
    chmod 700 "$HOME_DIR/.ssh"
    chmod 600 "$HOME_DIR/.ssh/authorized_keys"
    chown -R "$USERNAME":"$USERNAME" "$HOME_DIR/.ssh"
    log "Added SSH public key for '$USERNAME'."
  fi
fi

# ---------- SSH hardening ----------
SSHD="/etc/ssh/sshd_config"
if [[ -f "$SSHD" ]]; then
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD"
  if $DISABLE_PW_LOGIN; then
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD"
  fi
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD"
  sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD"
  systemctl restart ssh || systemctl restart sshd || warn "Failed to restart SSH service"
  log "SSHD hardened (root login disabled; password login: $($DISABLE_PW_LOGIN && echo off || echo on))."
else
  warn "SSHD config not found at $SSHD"
fi

# ---------- Firewall ----------
IFS=',' read -ra PORTS <<< "$UFW_PORTS"
if has_cmd ufw; then
  ufw --force enable || true
  ufw default deny incoming
  ufw default allow outgoing
  for p in "${PORTS[@]}"; do ufw allow "$p"; done
  ufw status verbose || true
  log "Configured UFW with allowed ports: ${UFW_PORTS}"
elif has_cmd firewall-cmd; then
  systemctl enable --now firewalld || true
  for p in "${PORTS[@]}"; do
    if [[ "$p" =~ ^[0-9]+$ ]]; then
      firewall-cmd --permanent --add-port="${p}/tcp" || true
    else
      firewall-cmd --permanent --add-service="$p" || true
    fi
  done
  firewall-cmd --reload || true
  firewall-cmd --list-all || true
  log "Configured firewalld with allowed: ${UFW_PORTS}"
else
  warn "No supported firewall (ufw or firewalld) found."
fi

# ---------- Fail2ban basic ----------
cat >/etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF

systemctl enable --now fail2ban || warn "fail2ban enable failed"
log "fail2ban configured and started."

# ---------- Unattended upgrades (Debian/Ubuntu) ----------
if [[ "$PKG" == "apt" ]]; then
  apt-get install -y unattended-upgrades apt-listchanges
  dpkg-reconfigure -f noninteractive unattended-upgrades || true
  log "Unattended upgrades enabled on Debian/Ubuntu."
fi

# ---------- Basic MOTD with system info ----------
cat >/etc/motd <<'EOF'
Welcome! This server is managed by bootstrap-server.sh
- SSH root login: disabled
- Check: sudo systemctl status fail2ban
- Firewall: ufw/firewalld enabled
EOF

log "All done. Please test SSH access with your non-root user before closing the current session."
