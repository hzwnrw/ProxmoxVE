#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://dorkmost.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  redis \
  jq \
  make
msg_ok "Installed Dependencies"

HOST_IP=$(hostname -I | awk '{print $1}')
NODE_VERSION="22" NODE_MODULE="pnpm@$(curl -s https://raw.githubusercontent.com/Vito0912/forkmost/refs/heads/personal/package.json | jq -r '.packageManager | split("@")[1]')" setup_nodejs
PG_VERSION="16" setup_postgresql
fetch_and_deploy_gh_release "forkmost" "Vito0912/forkmost"

msg_info "Setting up PostgreSQL"
DB_NAME="forkmost_db"
DB_USER="forkmost_user"
DB_PASS="$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-13)"
$STD sudo -u postgres psql -c "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';"
$STD sudo -u postgres psql -c "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER ENCODING 'UTF8' TEMPLATE template0;"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET client_encoding TO 'utf8';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET default_transaction_isolation TO 'read committed';"
$STD sudo -u postgres psql -c "ALTER ROLE $DB_USER SET timezone TO 'UTC'"
{
  echo "Forkmost-Credentials"
  echo "Database Name: $DB_NAME"
  echo "Database User: $DB_USER"
  echo "Database Password: $DB_PASS"
} >>~/forkmost.creds
msg_ok "Set up PostgreSQL"

msg_info "Configuring Forkmost (Patience)"
cd /opt/forkmost
mv .env.example .env
mkdir data
sed -i -e "s|APP_SECRET=.*|APP_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)|" \
  -e "s|DATABASE_URL=.*|DATABASE_URL=postgres://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME|" \
  -e "s|FILE_UPLOAD_SIZE_LIMIT=.*|FILE_UPLOAD_SIZE_LIMIT=50mb|" \
  -e "s|DRAWIO_URL=.*|DRAWIO_URL=https://embed.diagrams.net|" \
  -e "s|DISABLE_TELEMETRY=.*|DISABLE_TELEMETRY=true|" \
  -e "s|APP_URL=.*|APP_URL=http://$HOST_IP:3000|" \
  /opt/forkmost/.env
export NODE_OPTIONS="--max-old-space-size=2048"
$STD pnpm install
$STD pnpm build
msg_ok "Configured Forkmost"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/forkmost.service
[Unit]
Description=Forkmost Service
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/forkmost
ExecStart=/usr/bin/pnpm start
Restart=always
EnvironmentFile=/opt/forkmost/.env

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now forkmost
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
$STD apt -y clean
msg_ok "Cleaned"
