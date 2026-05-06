#!/usr/bin/env bash
# Перезапуск всех запущенных контейнеров стека docker-compose:
# приложения подхватывают переменные окружения при старте, edge-nginx — конфиг и
# заново резолвит имена вида marketplace/ozon/factoring после их рестарта.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT/docker/docker-compose.yml"
ENV_FILE="$ROOT/.env"

usage() {
  printf '%s\n' "Использование: ./reload.sh [--help]"
  printf '%s\n' "Файлы: $COMPOSE_FILE, $ENV_FILE"
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

[[ -f "$ENV_FILE" ]] || { echo "Нет $ENV_FILE — сначала install или скопируйте env.example."; exit 1; }

compose() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

mapfile -t running < <(compose ps --status running --services 2>/dev/null || true)

if [[ "${#running[@]}" -eq 0 ]]; then
  echo "[reload] Нет контейнеров в статусе running. Поднимите стек: ./run.sh"
  exit 0
fi

for svc in "${running[@]}"; do
  [[ "$svc" == edge-nginx ]] && continue
  printf '[reload] restart %s\n' "$svc"
  compose restart "$svc"
done

if printf '%s\n' "${running[@]}" | grep -qx edge-nginx; then
  printf '[reload] restart edge-nginx (конфиг с томов + актуальный DNS upstream)\n'
  compose restart edge-nginx
fi

echo '[reload] готово. Статус: docker compose -f docker/docker-compose.yml --env-file .env ps'
