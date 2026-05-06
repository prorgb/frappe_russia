#!/usr/bin/env bash
# Установка зависимостей на Linux Mint / Ubuntu-совместимых системах,
# подготовка .env и загрузка образов Docker для стека ERPNext v16.17.0.
#
# Важно: ядро ERPNext использует MariaDB. PostgreSQL в compose — для MarketPlace,
# Factoring и других сервисов. Сборка ERPNext из исходников не требуется:
# используются официальные образы frappe/erpnext (тег задаётся в .env).
#
# Репликация при росте нагрузки (кратко):
#   — Масштабирование воркеров: docker compose up -d --scale queue-short=2 --scale queue-long=2
#   — HA БД: вынести MariaDB в Galera / облачный кластер и указать DB_HOST в override.
#   — Несколько нод приложения: общий volume sites (NFS) и один MariaDB; см. документацию Frappe.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT/docker/docker-compose.yml"

log() { printf '%s\n' "$*"; }
die() { log "Ошибка: $*"; exit 1; }

[[ -f "$COMPOSE_FILE" ]] || die "Не найден $COMPOSE_FILE (запускайте из корня репозитория)."

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "Запустите от root: sudo $0"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  ca-certificates curl git jq gnupg lsb-release \
  apt-transport-https software-properties-common

# Docker (пакеты из репозитория дистрибутива — стабильно для Mint)
if ! command -v docker >/dev/null 2>&1; then
  apt-get install -y docker.io docker-compose-v2
fi

systemctl enable --now docker 2>/dev/null || true

if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG docker "$SUDO_USER" || true
  log "Пользователь $SUDO_USER добавлен в группу docker. Перелогиньтесь при необходимости."
fi

gen_pw() { openssl rand -base64 24 | tr -d '/+=' | head -c 32; }

if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/env.example" "$ROOT/.env"
  MYSQL_PW="$(gen_pw)"
  PG_PW="$(gen_pw)"
  FRAPPE_PW="$(gen_pw)"
  sed -i \
    -e "s/^MYSQL_ROOT_PASSWORD=.*/MYSQL_ROOT_PASSWORD=${MYSQL_PW}/" \
    -e "s/^MARIADB_ROOT_PASSWORD=.*/MARIADB_ROOT_PASSWORD=${MYSQL_PW}/" \
    -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${PG_PW}/" \
    -e "s/^FRAPPE_ADMIN_PASSWORD=.*/FRAPPE_ADMIN_PASSWORD=${FRAPPE_PW}/" \
    "$ROOT/.env"
  chmod 600 "$ROOT/.env"
  log "Создан файл .env с случайными паролями (MariaDB root, PostgreSQL, админ Frappe)."
else
  log "Файл .env уже существует — не перезаписываю."
fi

log "Загрузка образов (нужен интернет)..."
docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" pull

log "Сборка образов helper-заглушек..."
docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" build marketplace ozon factoring

log "Готово."
log ""
log "Дальше:"
log "  1) Настройте DNS: A-запись для FRAPPE_SITE_NAME из .env (например erp.maxon24.online) и при необходимости maxon24.online → IP сервера."
log "  2) Запуск: cd $ROOT && sudo -u ${SUDO_USER:-$USER} ./run.sh"
log "  3) Первый раз создать сайт Frappe (один раз):"
log "       cd $ROOT && sudo -u ${SUDO_USER:-$USER} INIT=1 ./run.sh"
log ""
log "HTTPS: выпустите сертификаты (certbot) на хосте или добавьте второй server в docker/nginx/conf.d/ и пробросьте 443 в edge-nginx."

chmod +x "$ROOT/install.sh" "$ROOT/run.sh" 2>/dev/null || true
