#!/usr/bin/env bash
# Run on the explicitly authorized Ubuntu VPS; creates only Tolk-owned resources.
set -euo pipefail
tolk_host="${1:?Provide the chosen hostname}"
[[ "$tolk_host" =~ ^[a-z0-9.-]+$ ]] || exit 2
tolk_root=/opt/tolk-web
test ! -e "$tolk_root" || { echo 'Tolk directory already exists; review before updating.'; exit 3; }
test ! -e /etc/nginx/conf.d/tolk-web.conf
nginx -t
install -d -m 755 "$tolk_root"
tar -xzf /tmp/tolk-web-source-20261102.tgz --no-same-owner -C "$tolk_root"
install -d -m 700 -o 10001 -g 10001 "$tolk_root/data" "$tolk_root/secrets"
python3 - "$tolk_root/secrets/activation" <<'PY'
import os, secrets, sys
descriptor = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, 'w') as output: output.write(secrets.token_urlsafe(24))
os.chown(sys.argv[1], 10001, 10001)
PY
printf 'TOLK_ORIGIN=https://%s\n' "$tolk_host" > "$tolk_root/.env"
chmod 600 "$tolk_root/.env"
cd "$tolk_root"
docker compose -p tolk-web build --pull
docker run --rm --user root -v "$tolk_root/secrets:/keys" tolk-web-web python -c 'import os;from push import create_key;create_key("/keys/vapid.pem");os.chown("/keys/vapid.pem",10001,10001)'
docker compose -p tolk-web up -d
tolk_ready=false
for _ in {1..20}; do
  if curl --fail --silent -H "Host: $tolk_host" http://127.0.0.1:18787/api/session >/dev/null; then tolk_ready=true; break; fi
  sleep 2
done
test "$tolk_ready" = true
install -d -m 755 /var/lib/tolk-acme
cat > /etc/nginx/conf.d/tolk-web.conf <<EOF
server {
    listen 80;
    server_name $tolk_host;
    location ^~ /.well-known/acme-challenge/ { root /var/lib/tolk-acme; }
    location / { return 404; }
}
EOF
nginx -t
systemctl reload nginx
certbot certonly --webroot -w /var/lib/tolk-acme -d "$tolk_host" --non-interactive --agree-tos --register-unsafely-without-email
cp /etc/nginx/conf.d/tolk-web.conf "$tolk_root/nginx-http-before-tls.conf"
cat > /etc/nginx/conf.d/tolk-web.conf <<EOF
limit_req_zone \$binary_remote_addr zone=tolk_login:1m rate=10r/m;
limit_req_zone \$binary_remote_addr zone=tolk_api:1m rate=10r/s;
server {
    listen 80;
    server_name $tolk_host;
    location ^~ /.well-known/acme-challenge/ { root /var/lib/tolk-acme; }
    location / { return 301 https://$tolk_host\$request_uri; }
}
server {
    listen 443 ssl;
    server_name $tolk_host;
    ssl_certificate /etc/letsencrypt/live/$tolk_host/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$tolk_host/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 8m;
    access_log /var/log/nginx/tolk-web.access.log;
    error_log /var/log/nginx/tolk-web.error.log warn;
    location ~ ^/api/(login|setup)\$ {
        limit_req zone=tolk_login burst=5 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:18787;
        proxy_set_header Host $tolk_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
    location / {
        limit_req zone=tolk_api burst=30 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:18787;
        proxy_set_header Host $tolk_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_connect_timeout 5s;
        proxy_read_timeout 35s;
    }
}
EOF
if ! nginx -t; then
  cp "$tolk_root/nginx-http-before-tls.conf" /etc/nginx/conf.d/tolk-web.conf
  exit 4
fi
systemctl reload nginx
cat > /etc/cron.d/tolk-web-backup <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
23 2 * * * root cd /opt/tolk-web && docker compose -p tolk-web exec -T web python backup.py > /dev/null
EOF
chmod 644 /etc/cron.d/tolk-web-backup
docker compose -p tolk-web exec -T web python backup.py
curl --fail --silent "https://$tolk_host/api/session"
printf '\nTolk preview deployed. No user account has been created.\n'
