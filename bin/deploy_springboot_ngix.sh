#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Spring Boot + systemd + Nginx (HTTP/HTTPS)
# Ubuntu 20.04/22.04/24.04
# Idempotent & includes uninstall
# ============================================

# ---------- Defaults (override with flags) ----------
APP_NAME="iwa-java"
JAR_SRC=""
DOMAIN=""
EMAIL=""
APP_USER="springboot"
APP_GROUP="springboot"
INSTALL_DIR=""
ENV_DIR=""
ENV_FILE=""
SERVICE_FILE=""
NGINX_AVAIL=""
NGINX_ENABLED=""
APP_PORT=8080
BIND_ADDRESS="127.0.0.1"
SPRING_PROFILES_ACTIVE="prod"
JAVA_OPTS="-Xms256m -Xmx512m"
ENABLE_HTTPS=false
CONFIGURE_UFW=false
INSTALL_JAVA=true
REMOVE=false

# ---------- Colors ----------
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red() { printf "\033[31m%s\033[0m\n" "$*"; }

# ---------- Helpers ----------
usage() {
  cat <<EOF
Usage: $0 [options]

Required (for fresh deploy):
  --jar PATH              Path to Spring Boot JAR (copied to /opt/<name>/<name>.jar)

Common options:
  --name NAME             Application name (default: myapp)
  --port N                Internal app port (default: 8080)
  --profile PROFILE       Spring profile (default: prod)
  --java-opts "OPTS"      JAVA_OPTS for JVM (default: "-Xms256m -Xmx512m")
  --no-java-install       Skip OpenJDK install (if Java already present)

Nginx / HTTPS:
  --domain DOMAIN         Public domain (e.g., example.com)
  --email EMAIL           Email for Let's Encrypt
  --https                 Enable HTTPS via certbot (requires --domain and --email)

Firewall:
  --ufw                   Configure UFW: allow OpenSSH + Nginx Full

Maintenance:
  --remove                Uninstall app + Nginx vhost (attempt to keep certs)
  -h, --help              Show help

Examples:
  sudo $0 --name myapp --jar /tmp/app.jar
  sudo $0 --name api --jar ./api.jar --domain api.example.com --email admin@example.com --https --ufw
EOF
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    red "Please run as root (sudo)."
    exit 1
  fi
}

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    cp -a "$path" "${path}.$(date +%Y%m%d%H%M%S).bak"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) APP_NAME="$2"; shift 2 ;;
      --jar) JAR_SRC="$2"; shift 2 ;;
      --domain) DOMAIN="$2"; shift 2 ;;
      --email) EMAIL="$2"; shift 2 ;;
      --port) APP_PORT="$2"; shift 2 ;;
      --profile) SPRING_PROFILES_ACTIVE="$2"; shift 2 ;;
      --java-opts) JAVA_OPTS="$2"; shift 2 ;;
      --https) ENABLE_HTTPS=true; shift ;;
      --ufw) CONFIGURE_UFW=true; shift ;;
      --no-java-install) INSTALL_JAVA=false; shift ;;
      --remove) REMOVE=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) red "Unknown option: $1"; usage; exit 1 ;;
    esac
  done

  INSTALL_DIR="/opt/${APP_NAME}"
  ENV_DIR="/etc/${APP_NAME}"
  ENV_FILE="${ENV_DIR}/${APP_NAME}.env"
  SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
  NGINX_AVAIL="/etc/nginx/sites-available/${APP_NAME}"
  NGINX_ENABLED="/etc/nginx/sites-enabled/${APP_NAME}"

  if [[ "$REMOVE" == false ]]; then
    if [[ -z "${JAR_SRC}" || ! -f "${JAR_SRC}" ]]; then
      yellow "JAR not provided or not found. You can still proceed if the app is already installed."
    fi
    if [[ "$ENABLE_HTTPS" == true ]]; then
      if [[ -z "${DOMAIN}" || -z "${EMAIL}" ]]; then
        red "--https requires both --domain and --email"
        exit 1
      fi
    fi
  fi
}

apt_install() {
  green "Installing packages..."
  apt-get update -y
  apt-get install -y nginx curl ca-certificates
  if [[ "$INSTALL_JAVA" == true ]]; then
    if ! command -v java >/dev/null 2>&1; then
      apt-get install -y openjdk-17-jre-headless
    fi
  fi
  if [[ "$ENABLE_HTTPS" == true ]]; then
    apt-get install -y certbot python3-certbot-nginx
  fi
  if [[ "$CONFIGURE_UFW" == true ]]; then
    apt-get install -y ufw
  fi
}

create_user() {
  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    green "Creating user: $APP_USER"
    adduser --system --no-create-home --group "$APP_USER"
  fi
}

install_app() {
  mkdir -p "$INSTALL_DIR"
  chown -R "$APP_USER:$APP_GROUP" "$INSTALL_DIR"
  if [[ -n "${JAR_SRC}" && -f "${JAR_SRC}" ]]; then
    green "Copying JAR to $INSTALL_DIR/${APP_NAME}.jar"
    cp -f "${JAR_SRC}" "${INSTALL_DIR}/${APP_NAME}.jar"
    chown "$APP_USER:$APP_GROUP" "${INSTALL_DIR}/${APP_NAME}.jar"
    chmod 640 "${INSTALL_DIR}/${APP_NAME}.jar"
  else
    yellow "Skipping JAR copy (not provided). Assuming it already exists in $INSTALL_DIR/${APP_NAME}.jar"
  fi
}

write_env_file() {
  mkdir -p "$ENV_DIR"
  backup_if_exists "$ENV_FILE"
  cat > "$ENV_FILE" <<EOF
# Managed by deploy script for $APP_NAME
SPRING_PROFILES_ACTIVE=${SPRING_PROFILES_ACTIVE}
SERVER_PORT=${APP_PORT}
SERVER_ADDRESS=${BIND_ADDRESS}
JAVA_OPTS=${JAVA_OPTS}
# Add your custom environment variables below:
# EXAMPLE_API_KEY=changeme
EOF
  chmod 640 "$ENV_FILE"
  chown root:"$APP_GROUP" "$ENV_FILE" || true
}

write_systemd_service() {
  backup_if_exists "$SERVICE_FILE"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=${APP_NAME} Spring Boot Service
After=network-online.target
Wants=network-online.target

[Service]
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/java \$JAVA_OPTS -jar ${INSTALL_DIR}/${APP_NAME}.jar
SuccessExitStatus=143
Restart=always
RestartSec=5

# Security Hardening
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ProtectControlGroups=true
ProtectKernelTunables=true
ProtectKernelLogs=true
ProtectClock=true
MemoryDenyWriteExecute=true
ReadWritePaths=${INSTALL_DIR} ${ENV_DIR}
LockPersonality=true
CapabilityBoundingSet=
AmbientCapabilities=
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${APP_NAME}" >/dev/null 2>&1 || true
}

start_service() {
  systemctl restart "${APP_NAME}"
  sleep 1
  systemctl --no-pager --full status "${APP_NAME}" || true
}

configure_nginx_http() {
  backup_if_exists "$NGINX_AVAIL"
  cat > "$NGINX_AVAIL" <<'EOF'
# Managed by deploy script
server {
    listen 80;
    # server_name will be replaced below if DOMAIN is set
    server_name _;

    # Increase buffer for large headers if needed
    large_client_header_buffers 4 16k;

    location / {
        proxy_pass http://127.0.0.1:APP_PORT_REPLACE;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }
}
EOF

  # Replace port
  sed -i "s/APP_PORT_REPLACE/${APP_PORT}/g" "$NGINX_AVAIL"

  # If DOMAIN provided, set it explicitly
  if [[ -n "$DOMAIN" ]]; then
    sed -i "s/server_name _;/server_name ${DOMAIN};/g" "$NGINX_AVAIL"
  fi

  ln -sf "$NGINX_AVAIL" "$NGINX_ENABLED"

  # Remove default nginx site if present
  if [[ -e /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
  fi

  nginx -t
  systemctl reload nginx
}

configure_https_certbot() {
  if [[ "$ENABLE_HTTPS" == true ]]; then
    green "Requesting Let's Encrypt certificate for ${DOMAIN}"
    # Ensure the server_name matches the domain in the active site
    sed -i "s/server_name .*/server_name ${DOMAIN};/g" "$NGINX_AVAIL"
    nginx -t && systemctl reload nginx
    certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" --redirect
    systemctl reload nginx
  fi
}

configure_ufw() {
  if [[ "$CONFIGURE_UFW" == true ]]; then
    green "Configuring UFW..."
    ufw allow OpenSSH || true
    if [[ "$ENABLE_HTTPS" == true ]]; then
      ufw allow "Nginx Full" || true
      ufw delete allow "Nginx HTTP" >/dev/null 2>&1 || true
    else
      ufw allow "Nginx HTTP" || true
    fi
    ufw --force enable
    ufw status verbose || true
  fi
}

post_checks() {
  green "Post-deploy checks:"
  systemctl is-active --quiet "${APP_NAME}" && green "✔ systemd service is active" || yellow "⚠ service not active"
  nginx -t && green "✔ Nginx config OK" || red "✖ Nginx config error"
  if [[ -n "$DOMAIN" ]]; then
    echo "Try: curl -I http://${DOMAIN}/"
    if [[ "$ENABLE_HTTPS" == true ]]; then
      echo "Try: curl -I https://${DOMAIN}/"
    fi
  fi
  echo "Logs: journalctl -u ${APP_NAME} -f"
}

uninstall_all() {
  yellow "Stopping and disabling ${APP_NAME}..."
  systemctl stop "${APP_NAME}" || true
  systemctl disable "${APP_NAME}" || true

  yellow "Removing systemd service file..."
  rm -f "${SERVICE_FILE}"
  systemctl daemon-reload || true

  yellow "Removing Nginx site..."
  rm -f "${NGINX_ENABLED}" "${NGINX_AVAIL}"
  nginx -t && systemctl reload nginx || true

  yellow "Leaving certs in /etc/letsencrypt (you can remove manually if desired)."

  yellow "Removing app directories..."
  rm -rf "${INSTALL_DIR}" "${ENV_DIR}"

  green "Uninstall complete for ${APP_NAME}."
}

main() {
  require_root
  parse_args "$@"

  if [[ "$REMOVE" == true ]]; then
    uninstall_all
    exit 0
  fi

  apt_install
  create_user
  install_app
  write_env_file
  write_systemd_service
  start_service
  configure_nginx_http
  configure_https_certbot
  configure_ufw
  post_checks

  cat <<SUMMARY

====================================================
Deployment complete for: ${APP_NAME}
App dir:       ${INSTALL_DIR}
Env file:      ${ENV_FILE}
Service:       systemctl status ${APP_NAME}
Nginx site:    ${NGINX_AVAIL}
Domain:        ${DOMAIN:-"(none - using _)"}
HTTPS:         $( [[ "$ENABLE_HTTPS" == true ]] && echo "enabled" || echo "disabled" )
UFW:           $( [[ "$CONFIGURE_UFW" == true ]] && echo "configured" || echo "not configured" )
====================================================

SUMMARY
}

main "$@"
``