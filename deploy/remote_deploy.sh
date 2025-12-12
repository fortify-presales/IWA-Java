#!/usr/bin/env bash
set -euo pipefail

# remote_deploy.sh
# Usage: remote_deploy.sh [--dry-run] /path/to/uploaded.jar
# --dry-run will print the actions that would be taken without performing changes

APP_NAME="iwa"
APP_USER="deploy"
DEPLOY_DIR="/opt/${APP_NAME}"
RELEASES_DIR="${DEPLOY_DIR}/releases"
SHARED_DIR="${DEPLOY_DIR}/shared"
KEEP_RELEASES=5
HEALTH_URL="http://127.0.0.1:8080/actuator/health"
HEALTH_TIMEOUT=60

DRY_RUN=false

# simple helper to either run a command or print it in dry-run mode
exec_cmd() {
  if [ "${DRY_RUN}" = true ]; then
    echo "[dry-run] $*"
  else
    eval "$*"
  fi
}

# parse args
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 [--dry-run] /path/to/artifact.jar" >&2
  exit 2
fi

if [ "$1" = "--dry-run" ]; then
  DRY_RUN=true
  shift
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 [--dry-run] /path/to/artifact.jar" >&2
  exit 2
fi

ARTIFACT_PATH="$1"
if [ ! -f "${ARTIFACT_PATH}" ]; then
  echo "Artifact not found: ${ARTIFACT_PATH}" >&2
  exit 3
fi

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
NEW_RELEASE_DIR="${RELEASES_DIR}/${TIMESTAMP}"

# Ensure directories exist (create or show in dry-run)
exec_cmd "sudo mkdir -p \"${RELEASES_DIR}\""
exec_cmd "sudo mkdir -p \"${SHARED_DIR}\""
exec_cmd "sudo chown -R ${APP_USER}:${APP_USER} \"${DEPLOY_DIR}\""

# Ensure /etc/default/iwa exists and contains unquoted NAME=VALUE lines
if [ ! -f /etc/default/iwa ]; then
  if [ "${DRY_RUN}" = true ]; then
    echo "[dry-run] Would create /etc/default/iwa with default JAVA_OPTS and SPRING_MAIL_TEST_CONNECTION=false"
  else
    sudo bash -c 'cat > /etc/default/iwa <<\'EOF\'
JAVA_OPTS="-Xms256m -Xmx512m -Djava.security.egd=file:/dev/./urandom -Dspring.profiles.active=prod"
# Enable skipping of SMTP connection test at startup to avoid failing boot when no SMTP configured
SPRING_MAIL_TEST_CONNECTION=false
# SPRING_DATASOURCE_URL=jdbc:postgresql://db.example:5432/iwa
# SPRING_DATASOURCE_USERNAME=iwa
# SPRING_DATASOURCE_PASSWORD=supersecret
EOF'
    sudo chown root:root /etc/default/iwa
    sudo chmod 640 /etc/default/iwa
  fi
else
  # sanitize any quoted lines ("..." or '...') so systemd can parse them
  exec_cmd "sudo sed -i -E 's/^[[:space:]]*\"(.*)\"[[:space:]]*$/\\1/' /etc/default/iwa || true"
  exec_cmd "sudo sed -i -E \"s/^[[:space:]]*'(.*)'[[:space:]]*$/\\1/\" /etc/default/iwa || true" || true
  # Note: second sed uses a safe pattern; if platform sed behaves differently it's a no-op
fi

# Prepare new release
if [ "${DRY_RUN}" = true ]; then
  echo "[dry-run] Would create new release dir: ${NEW_RELEASE_DIR}"
  echo "[dry-run] Would copy ${ARTIFACT_PATH} -> ${NEW_RELEASE_DIR}/<artifact>"
else
  sudo -u ${APP_USER} mkdir -p "${NEW_RELEASE_DIR}"
  ARTIFACT_BASENAME=$(basename "${ARTIFACT_PATH}")
  sudo cp "${ARTIFACT_PATH}" "${NEW_RELEASE_DIR}/${ARTIFACT_BASENAME}"
  sudo chown ${APP_USER}:${APP_USER} "${NEW_RELEASE_DIR}/${ARTIFACT_BASENAME}"
  # Create a stable jar name expected by systemd (iwa.jar) inside the release
  sudo -u ${APP_USER} ln -sfn "${NEW_RELEASE_DIR}/${ARTIFACT_BASENAME}" "${NEW_RELEASE_DIR}/iwa.jar" || true
  sudo chown -h ${APP_USER}:${APP_USER} "${NEW_RELEASE_DIR}/iwa.jar" || true
fi

# Link shared config (if any)
if [ -d "${SHARED_DIR}/config" ]; then
  if [ "${DRY_RUN}" = true ]; then
    echo "[dry-run] Would link shared config: ${SHARED_DIR}/config -> ${NEW_RELEASE_DIR}/config"
  else
    sudo -u ${APP_USER} ln -sfn "${SHARED_DIR}/config" "${NEW_RELEASE_DIR}/config" || true
  fi
fi

# Atomic switch of current symlink and service restart
if [ "${DRY_RUN}" = true ]; then
  echo "[dry-run] Would create atomic symlink: ${DEPLOY_DIR}/current -> ${NEW_RELEASE_DIR}"
  echo "[dry-run] Would restart systemd service: ${APP_NAME}.service"
  echo "[dry-run] Skipping health check and cleanup in dry-run mode"
else
  sudo ln -sfn "${NEW_RELEASE_DIR}" "${DEPLOY_DIR}/current_next"
  sudo chown -h ${APP_USER}:${APP_USER} "${DEPLOY_DIR}/current_next"
  sudo mv -T "${DEPLOY_DIR}/current_next" "${DEPLOY_DIR}/current"

  # Restart systemd service
  sudo systemctl restart ${APP_NAME}.service

  # Wait for health
  echo "Waiting for health endpoint ${HEALTH_URL}"
  SECS_WAITED=0
  until curl -fsS --max-time 5 ${HEALTH_URL} >/dev/null 2>&1; do
    sleep 2
    SECS_WAITED=$((SECS_WAITED + 2))
    if [ ${SECS_WAITED} -ge ${HEALTH_TIMEOUT} ]; then
      echo "Health check failed after ${HEALTH_TIMEOUT}s, attempting rollback" >&2
      # find previous release
      PREV=$(ls -1dt ${RELEASES_DIR}/* | sed -n '2p' || true)
      if [ -n "${PREV}" ]; then
        echo "Rolling back to ${PREV}"
        sudo ln -sfn "${PREV}" "${DEPLOY_DIR}/current"
        sudo systemctl restart ${APP_NAME}.service || true
      fi
      exit 4
    fi
  done

  echo "Health check succeeded"

  # Cleanup old releases
  COUNT=$(ls -1dt ${RELEASES_DIR}/* | wc -l || true)
  if [ "${COUNT}" -gt "${KEEP_RELEASES}" ]; then
    TO_DELETE=$(ls -1dt ${RELEASES_DIR}/* | tail -n +$((KEEP_RELEASES+1)))
    for r in ${TO_DELETE}; do
      echo "Removing old release: ${r}"
      sudo rm -rf "${r}"
    done
  fi
fi

if [ "${DRY_RUN}" = true ]; then
  echo "[dry-run] Deploy simulation complete. No changes were made."
else
  echo "Deploy complete. Current -> $(readlink -f ${DEPLOY_DIR}/current)"
fi

exit 0
