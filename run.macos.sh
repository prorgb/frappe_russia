#!/usr/bin/env bash
# Запуск всех контейнеров на macOS.
# Первичное создание сайта Frappe: INIT=1 ./run.macos.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT/docker/docker-compose.yml"
ENV_FILE="$ROOT/.env"

[[ -f "$ENV_FILE" ]] || { echo "Нет $ENV_FILE — сначала ./install.macos.sh"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Docker CLI не найден. Установите Docker Desktop."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker daemon недоступен. Запустите Docker Desktop."; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

cd "$ROOT"

compose() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

if [[ "${INIT:-}" == "1" ]]; then
  printf '[init] Поднимаю MariaDB и Redis...\n'
  compose up -d db redis-cache redis-queue
  printf '[init] Запускаю configurator...\n'
  compose up -d configurator
  cid="$(compose ps -aq configurator | head -n1)"
  if [[ -n "$cid" ]]; then
    printf '[init] Ожидаю завершения configurator (контейнер %s)...\n' "$cid"
    ec="$(docker wait "$cid" 2>/dev/null || echo 1)"
    if [[ "$ec" != "0" ]]; then
      echo "Configurator завершился с кодом $ec. Смотрите: docker logs $cid"
      exit 1
    fi
  fi
  printf '[init] Создаю сайт %s (если ещё нет)...\n' "${FRAPPE_SITE_NAME}"
  compose --profile init run --rm create-site
  printf '[init] Готово.\n'
fi

compose up -d

echo "Контейнеры запущены. HTTP: порт ${HTTP_PORT:-80}"
echo "Статус: docker compose -f docker/docker-compose.yml --env-file .env ps"

if [[ "${INIT:-}" != "1" ]] && ! compose exec -T backend test -f "sites/${FRAPPE_SITE_NAME}/site_config.json" 2>/dev/null; then
  echo "Подсказка: если сайт Frappe ещё не создан, один раз выполните: INIT=1 $ROOT/run.macos.sh"
fi
