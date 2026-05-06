# Режим порта 80: по умолчанию proxy → HTTP без обязательного TLS.
include /etc/nginx/includes/maxon24.online-http-mode-proxy.inc;

# С maxon24.online-https.conf (Let's Encrypt уже выдан): закомментируйте строку выше и раскомментируйте следующую — редирект на HTTPS:
# include /etc/nginx/includes/maxon24.online-http-mode-redirect.inc;
