#!/usr/bin/env bash
# Сборка выбранных сервисов из build: в docker-compose и пересоздание контейнеров.
# После пересборки microservices перезапускается edge-nginx (обновление upstream).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT/docker/docker-compose.yml"
ENV_FILE="$ROOT/.env"

usage() {
  cat <<'EOF'
Использование: ./rebuild.sh [флаги]

Сборка образов (build в compose) и force-recreate контейнеров:
  --marketplace   сервис marketplace
  --ozon          сервис ozon
  --factoring     сервис factoring
  --all           все три сервиса выше

Дополнительно:
  --pull          docker compose pull для сервисов без build (образы из registry)
  --no-edge       не перезапускать edge-nginx после сборки (по умолчанию перезапуск)

Примеры:
  ./rebuild.sh --marketplace
  ./rebuild.sh --all --pull
EOF
}

[[ -f "$ENV_FILE" ]] || { echo "Нет $ENV_FILE — сначала install или скопируйте env.example."; exit 1; }

compose() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

declare -a BUILD_SVCS=()
PULL_IMAGES=false
RESTART_EDGE=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --marketplace)
      BUILD_SVCS+=(marketplace)
      ;;
    --ozon)
      BUILD_SVCS+=(ozon)
      ;;
    --factoring)
      BUILD_SVCS+=(factoring)
      ;;
    --all)
      BUILD_SVCS=(marketplace ozon factoring)
      ;;
    --pull)
      PULL_IMAGES=true
      ;;
    --no-edge)
      RESTART_EDGE=false
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

# уникальные имена, порядок первого вхождения
if [[ "${#BUILD_SVCS[@]}" -gt 0 ]]; then
  mapfile -t BUILD_SVCS < <(printf '%s\n' "${BUILD_SVCS[@]}" | awk '!a[$0]++')
fi

if [[ "${#BUILD_SVCS[@]}" -eq 0 ]]; then
  echo "Укажите хотя бы один флаг: --marketplace, --ozon, --factoring или --all"
  usage
  exit 1
fi

if $PULL_IMAGES; then
  printf '[rebuild] pull образов (без локального build)...\n'
  compose pull \
    db redis-cache redis-queue \
    postgres zookeeper kafka \
    backend frontend websocket \
    queue-short queue-long scheduler \
    edge-nginx
fi

printf '[rebuild] build %s\n' "${BUILD_SVCS[*]}"
compose build "${BUILD_SVCS[@]}"

printf '[rebuild] up --force-recreate %s\n' "${BUILD_SVCS[*]}"
compose up -d --force-recreate "${BUILD_SVCS[@]}"

if $RESTART_EDGE && compose ps --status running --services 2>/dev/null | grep -qx edge-nginx; then
  printf '[rebuild] restart edge-nginx\n'
  compose restart edge-nginx
fi

printf '[rebuild] готово.\n'
