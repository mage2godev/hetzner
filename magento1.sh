#!/bin/bash

# -----------------------------
# Magento 2 Full Auto Install
# Ubuntu 22.04
# PHP 8.1, Composer 2.2, MariaDB 10.5, Elasticsearch 7.17, Redis, Varnish, Memcached, NGINX, Git, SSL
# Domain: irelax.com.ua
# -----------------------------

set -e

DOMAIN="irelax.com.ua"
MAGENTO_DIR="/var/www/$DOMAIN"
DB_NAME="magento"
DB_USER="magento"
DB_PASS="234StrongPу45gassword123!"

echo "=== [14] Generate NGINX Config ==="

cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    root $MAGENTO_DIR/pub;
    index index.php;

    access_log /var/log/nginx/$DOMAIN-access.log;
    error_log /var/log/nginx/$DOMAIN-error.log;

    # Allow Certbot ACME challenge
    location ^~ /.well-known/acme-challenge/ {
        allow all;
        root $MAGENTO_DIR/pub;
    }

    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location /pub/ {
        alias $MAGENTO_DIR/pub/;
    }

    location /static/ {
        alias $MAGENTO_DIR/pub/static/;
    }

    location /media/ {
        alias $MAGENTO_DIR/pub/media/;
    }

    location ~* \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

echo "=== [15] SSL скопано — ключі налаштуєш пізніше ==="
echo "Пропускаю Certbot, бо поки що працюємо на HTTP."

echo "=== [16] HTTPS редирект теж пропускаємо ==="
echo "Коли додаси ключі — зробиш окремий сервер-блок listen 443 SSL."

echo "=== [17] Done! ==="
echo "Magento 2 працює на: http://$DOMAIN"
