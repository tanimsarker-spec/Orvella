#!/usr/bin/env bash
# One-time setup for a fresh Ubuntu 22.04/24.04 server. Run as root:
#   curl -fsSL https://raw.githubusercontent.com/YOUR-USER/YOUR-REPO/main/deploy/setup-server.sh -o setup.sh && sudo bash setup.sh
# (or copy this file to the server and run: sudo bash setup-server.sh)
# Safe to re-run: it keeps your existing JWT secret.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash setup-server.sh"
  exit 1
fi

read -rp "Your domain name (must already point at this server), e.g. party.example.com: " DOMAIN
[ -n "$DOMAIN" ] || { echo "Domain is required."; exit 1; }
read -rp "Google OAuth client ID (press Enter to skip Google Drive for now): " GID
GSECRET=""
if [ -n "$GID" ]; then
  read -rsp "Google OAuth client secret: " GSECRET
  echo
fi

echo "Email is used for password-reset codes. Press Enter to skip any of these (resets will be unavailable)."
read -rp "SMTP host (e.g. smtp.gmail.com): " SMTP_HOST
SMTP_PORT=587; SMTP_USER=""; SMTP_PASS=""; MAIL_FROM="Orvella <no-reply@$DOMAIN>"
if [ -n "$SMTP_HOST" ]; then
  read -rp "SMTP port [587]: " P; SMTP_PORT=${P:-587}
  read -rp "SMTP username: " SMTP_USER
  read -rsp "SMTP password: " SMTP_PASS; echo
  read -rp "Send emails from [$MAIL_FROM]: " F; MAIL_FROM=${F:-$MAIL_FROM}
fi

apt-get update -y
apt-get install -y ca-certificates curl rsync ufw openssl
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

mkdir -p /opt/orvella/deploy
ENVFILE=/opt/orvella/deploy/.env
if [ -f "$ENVFILE" ] && grep -q '^JWT_SECRET=.\{32,\}' "$ENVFILE"; then
  SECRET=$(grep '^JWT_SECRET=' "$ENVFILE" | cut -d= -f2-)
else
  SECRET=$(openssl rand -hex 32)
fi

if [ -f "$ENVFILE" ] && grep -q '^TURN_SECRET=.\{32,\}' "$ENVFILE"; then
  TURN=$(grep '^TURN_SECRET=' "$ENVFILE" | cut -d= -f2-)
else
  TURN=$(openssl rand -hex 32)
fi

umask 077
cat > "$ENVFILE" <<ENV
ORVELLA_DOMAIN=$DOMAIN
JWT_SECRET=$SECRET
GOOGLE_OAUTH_CLIENT_ID=$GID
GOOGLE_OAUTH_CLIENT_SECRET=$GSECRET
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASS=$SMTP_PASS
MAIL_FROM=$MAIL_FROM
TURN_SECRET=$TURN
ENV
chmod 600 "$ENVFILE"

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3478/tcp
ufw allow 3478/udp
ufw allow 49160:49200/udp
ufw --force enable

echo
echo "Server is ready. Next: in GitHub, run the 'Deploy server' workflow."
echo "Your site will be at: https://$DOMAIN"
