# Edge nginx (maxon24.online)

Обратный прокси перед ERPNext frontend и сервисами `marketplace`, `ozon`, `factoring`. Сервис в compose называется `edge-nginx`.

## Структура конфигурации

| Путь | Назначение |
|------|------------|
| [`conf.d/00-maxon24.online-shared.conf`](conf.d/00-maxon24.online-shared.conf) | Директива `map` для WebSocket и все `upstream` на контейнеры сети. Подключайте к любому варианту edge. |
| [`conf.d/maxon24.online-http.conf`](conf.d/maxon24.online-http.conf) | **Порт 80**: `/.well-known/acme-challenge/` (Certbot webroot) и режим для остальных запросов — см. `includes/maxon24.online-http-mode.inc`. |
| [`conf.d/maxon24.online-https.conf`](conf.d/maxon24.online-https.conf) | **Порт 443**, TLS и те же приложения через общий блок локаций. |
| [`includes/maxon24.online-app.inc`](includes/maxon24.online-app.inc) | Общие `proxy_*`, таймауты и все `location` (ERPNext, API-префиксы, factoring). |
| [`includes/maxon24.online-http-mode-proxy.inc`](includes/maxon24.online-http-mode-proxy.inc) | На 80 включить приложение по HTTP (проксирование, как для 443 без шифрования на edge). |
| [`includes/maxon24.online-http-mode-redirect.inc`](includes/maxon24.online-http-mode-redirect.inc) | На 80 у всех клиентских путей — редирект `301` на HTTPS (`https://$host$request_uri`). |
| [`includes/maxon24.online-http-mode.inc`](includes/maxon24.online-http-mode.inc) | Переключатель: активна либо ветка **proxy**, либо **redirect** (комментируйте вторую строку и раскомментируйте нужную пару строк). |

В `docker-compose.yml` монтируются:

- `./nginx/conf.d` → `/etc/nginx/conf.d`
- `./nginx/includes` → `/etc/nginx/includes`

Плюс хостовые тома `/etc/letsencrypt` и `/var/www/certbot` для выпуска и чтения сертификатов.

## Режимы порта 80

1. **Proxy (по умолчанию)** — чтобы edge поднимался **без файлов сертификата** или для локальной среды без TLS. Запросы идут в те же upstream, что и в HTTPS-режиме.
2. **Redirect** — включайте совместно с `maxon24.online-https.conf`, когда уже есть действующие сертификаты и нужно отправлять обычный HTTP на HTTPS. Путь для ACME `/.well-known/acme-challenge/` редиректу не затрагивается (его обрабатывает отдельный `location ^~`).

Отредактируйте [`includes/maxon24.online-http-mode.inc`](includes/maxon24.online-http-mode.inc).

## Инстансы: только HTTP / HTTP+HTTPS

- **Только HTTP:** оставьте в `conf.d/` файлы `00-maxon24.online-shared.conf` и `maxon24.online-http.conf`. Файл `maxon24.online-https.conf` уберите из каталога (например переименуйте в `maxon24.online-https.conf.off`) или не монтируйте альтернативный каталог конфигурации только с нужными файлами. При необходимости не пробрасывайте хост-порт **443**.
- **С TLS:** добавьте `maxon24.online-https.conf`, получите сертификаты (пути см. ниже), в `includes/maxon24.online-http-mode.inc` включите режим **redirect** вместо **proxy**.

## Сертификаты Let’s Encrypt

HTTPS-конфиг ожидает ключи здесь на **хосте** (монтируются в контейнер как есть):

- `/etc/letsencrypt/live/maxon24.online/fullchain.pem`
- `/etc/letsencrypt/live/maxon24.online/privkey.pem`

Выпуск (пример после настройки DNS и доступности порта 80 извне; webroot — `/var/www/certbot` на хосте):

```bash
sudo certbot certonly --webroot -w /var/www/certbot \
  -d maxon24.online -d www.maxon24.online -d erp.maxon24.online
```

После выпуска перезапустите контейнер `edge-nginx` (или выполните в корне репозитория `./reload.sh` — он так же подхватит обновление конфигов с томов).

## Скрипты перезапуска и сборки

В каталоге **корня репозитория** (рядом с `run.sh`):

| Файл | Действие |
|------|----------|
| [`../../reload.sh`](../../reload.sh) | Рестарт **всех** контейнеров в статусе `running`; `edge-nginx` перезапускается **последним**, чтобы заново резолвить upstream (`frontend`, `marketplace`, …) после их рестарта и поднять конфиг из `nginx/conf.d` и `nginx/includes`. |
| [`../../rebuild.sh`](../../rebuild.sh) | `docker compose build` и `up -d --force-recreate` для выбранных сервисов с директивой `build` в compose. Флаги: `--marketplace`, `--ozon`, `--factoring`, `--all`. Опционально `--pull` (обновление образов из registry для остального стека) и `--no-edge` (не трогать edge-nginx после сборки). |

## Домены и Frappe

`server_name` задаёт три имени: `maxon24.online`, `www.maxon24.online`, `erp.maxon24.online`. Имя сайта в ERPNext/Frappe обычно совпадает с субдоменом приложения (`erp.maxon24.online` в `.env` как `FRAPPE_SITE_NAME`).

## Имена файлов в `conf.d`

Файлы с суффиксом `.conf` в `conf.d/` подхватываются глобальным правилом `include` образа nginx. Файлы в `includes/` с расширением `.inc` **не** читаются автоматически — только там, где на них указан явный `include`.
