#!/usr/bin/env bash
# Установка зависимостей на macOS, подготовка .env
# и загрузка образов Docker для стека ERPNext v16.17.0.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT/docker/docker-compose.yml"
ENV_FILE="$ROOT/.env"

log() { printf '%s\n' "$*"; }
die() { log "Ошибка: $*"; exit 1; }

[[ -f "$COMPOSE_FILE" ]] || die "Не найден $COMPOSE_FILE (запускайте из корня репозитория)."

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдена команда '$1'. Установите её и повторите."
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    die "Docker CLI не найден. Установите Docker Desktop: https://www.docker.com/products/docker-desktop/"
  fi

  if ! docker info >/dev/null 2>&1; then
    die "Docker daemon недоступен. Запустите Docker Desktop и дождитесь статуса 'Engine running'."
  fi
}

gen_pw() { openssl rand -base64 24 | tr -d '/+=' | head -c 32; }

set_env_value() {
  local key="$1"
  local value="$2"
  local file="$3"
  local tmp
  tmp="$(mktemp)"
  awk -F= -v k="$key" -v v="$value" '
    BEGIN { done=0 }
    $1 == k { print k "=" v; done=1; next }
    { print $0 }
    END { if (!done) print k "=" v }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew не найден. Установите его: https://brew.sh/"
fi

log "Проверяю базовые утилиты..."
for cmd in curl git jq openssl; do
  ensure_cmd "$cmd"
done

ensure_docker

if [[ ! -f "$ENV_FILE" ]]; then
  [[ -f "$ROOT/env.example" ]] || die "Не найден $ROOT/env.example"
  cp "$ROOT/env.example" "$ENV_FILE"
  MYSQL_PW="$(gen_pw)"
  PG_PW="$(gen_pw)"
  FRAPPE_PW="$(gen_pw)"
  set_env_value "MYSQL_ROOT_PASSWORD" "$MYSQL_PW" "$ENV_FILE"
  set_env_value "MARIADB_ROOT_PASSWORD" "$MYSQL_PW" "$ENV_FILE"
  set_env_value "POSTGRES_PASSWORD" "$PG_PW" "$ENV_FILE"
  set_env_value "FRAPPE_ADMIN_PASSWORD" "$FRAPPE_PW" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  log "Создан файл .env со случайными паролями."
else
  log "Файл .env уже существует — не перезаписываю."
fi

log "Загрузка образов (нужен интернет)..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull

log "Сборка образов helper-заглушек..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build marketplace ozon factoring

log "Готово."
log ""
log "Дальше:"
log "  1) Запуск: cd $ROOT && ./run.macos.sh"
log "  2) Первый раз создать сайт Frappe (один раз):"
log "       cd $ROOT && INIT=1 ./run.macos.sh"

chmod +x "$ROOT/install.macos.sh" "$ROOT/run.macos.sh" 2>/dev/null || true
