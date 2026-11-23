#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="wifi-fleet-monitor"
APP_USER="wifi-fleet-monitor"
APP_GROUP="wifi-fleet"
APP_DIR="/opt/wifi-fleet-monitor"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this installer as root (sudo bash scripts/install_ubuntu.sh)." >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This installer supports Ubuntu/Debian systems with apt-get." >&2
    exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip nginx

getent group "${APP_GROUP}" >/dev/null || groupadd --system "${APP_GROUP}"
id -u "${APP_USER}" >/dev/null 2>&1 || useradd --system --gid "${APP_GROUP}" --home-dir "${APP_DIR}" --shell /usr/sbin/nologin "${APP_USER}"
usermod -a -G "${APP_GROUP}" www-data

install -d -o root -g "${APP_GROUP}" -m 0755 "${APP_DIR}"
install -d -o "${APP_USER}" -g "${APP_GROUP}" -m 0750 "${APP_DIR}/data"
install -d -o root -g "${APP_GROUP}" -m 0750 "${APP_DIR}/app" "${APP_DIR}/tests"
install -d -o root -g root -m 0755 "${APP_DIR}/deploy"

if [[ "${PROJECT_DIR}" != "${APP_DIR}" ]]; then
    cp -a "${PROJECT_DIR}/app/." "${APP_DIR}/app/"
    cp -a "${PROJECT_DIR}/tests/." "${APP_DIR}/tests/"
    cp -a "${PROJECT_DIR}/requirements.txt" "${PROJECT_DIR}/.env.example" "${APP_DIR}/"
    cp -a "${PROJECT_DIR}/deploy/wifi-fleet-monitor.service" "${APP_DIR}/deploy/"
    cp -a "${PROJECT_DIR}/deploy/wifi-fleet-monitor.nginx.conf" "${APP_DIR}/deploy/"
fi

chown -R root:"${APP_GROUP}" "${APP_DIR}/app" "${APP_DIR}/tests" "${APP_DIR}/deploy"
find "${APP_DIR}/app" "${APP_DIR}/tests" -type d -exec chmod 0750 {} +
find "${APP_DIR}/app" "${APP_DIR}/tests" -type f -exec chmod 0640 {} +

if [[ ! -x "${APP_DIR}/.venv/bin/python" ]]; then
    python3 -m venv "${APP_DIR}/.venv"
fi
"${APP_DIR}/.venv/bin/pip" install --upgrade pip
"${APP_DIR}/.venv/bin/pip" install -r "${APP_DIR}/requirements.txt"

if [[ ! -f "${APP_DIR}/.env" ]]; then
    install -o root -g "${APP_GROUP}" -m 0640 "${APP_DIR}/.env.example" "${APP_DIR}/.env"
    generated_token="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
    sed -i "s|^INGEST_TOKEN=.*|INGEST_TOKEN=${generated_token}|" "${APP_DIR}/.env"
    echo "Created ${APP_DIR}/.env with a generated ingestion token. Store that token securely."
else
    chown root:"${APP_GROUP}" "${APP_DIR}/.env"
    chmod 0640 "${APP_DIR}/.env"
fi

# The service account needs to read its environment; only root and the service
# group can access it. The parent directory remains traversable by the service.
chown root:"${APP_GROUP}" "${APP_DIR}/.env"
chmod 0640 "${APP_DIR}/.env"

# Uvicorn runs unprivileged and needs read/execute access to the virtualenv.
chown -R root:"${APP_GROUP}" "${APP_DIR}/.venv"
find "${APP_DIR}/.venv" -type d -exec chmod 0750 {} +
find "${APP_DIR}/.venv" -type f -exec chmod u+rwX,g+rX,o-rwx {} +

SERVICE_DEST="/etc/systemd/system/${APP_NAME}.service"
NGINX_DEST="/etc/nginx/sites-available/${APP_NAME}"
backup_existing() {
    local target="$1"
    if [[ -e "${target}" ]]; then
        cp -a "${target}" "${target}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    fi
}

backup_existing "${SERVICE_DEST}"
install -o root -g root -m 0644 "${PROJECT_DIR}/deploy/${APP_NAME}.service" "${SERVICE_DEST}"
backup_existing "${NGINX_DEST}"
install -o root -g root -m 0644 "${PROJECT_DIR}/deploy/${APP_NAME}.nginx.conf" "${NGINX_DEST}"

if [[ ! -e "/etc/nginx/sites-enabled/${APP_NAME}" ]]; then
    ln -s "${NGINX_DEST}" "/etc/nginx/sites-enabled/${APP_NAME}"
fi

systemctl daemon-reload
nginx -t
systemctl enable --now "${APP_NAME}"
systemctl reload nginx

echo "Installed ${APP_NAME}. Verify with: systemctl status ${APP_NAME}; curl --unix-socket /run/${APP_NAME}/uvicorn.sock http://localhost/health"
echo "If www-data was newly added to ${APP_GROUP}, restart nginx so workers receive the updated group membership."
