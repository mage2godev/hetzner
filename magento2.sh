#!/bin/bash

# ------------------ Змінні ------------------
DOMAIN="irelax.com.ua"
MAGENTO_VERSION="2.4.6-p9"
MAGENTO_DIR="/var/www/$DOMAIN"
DB_NAME="magento"
DB_USER="magento"
DB_PASS="magento_pass"
MYSQL_ROOT_PASS="root_pass"
ES_VERSION="7.17.22"

# ------------------ Magento ------------------
mkdir -p $MAGENTO_DIR
cd $MAGENTO_DIR

cat > ${$MAGENTO_DIR}/auth.json <<EOF
{
    "http-basic": {
        "repo.magento.com": {
            "username": "c5c73502f26b15c3d929a481280c862f",
            "password": "06f86d7b8cc8e508fd2878af817b9ba5"
        },
        "composer.amasty.com": {
          "username": "2d53536fa63b3a252ccab6be1d3c5ef2",
          "password": "abe8261618eca67a4dae2291ea1d98c2"
        }
    },
    "github-oauth": {
        "github.com": "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"
    }
}
EOF

# Встановлення Magento через Composer
composer create-project --repository=https://repo.magento.com/ magento/project-community-edition=$MAGENTO_VERSION .

# Налаштування прав
chown -R www-data:www-data $MAGENTO_DIR
find var generated vendor pub/static pub/media app/etc -type f -exec chmod g+w {} +
find var generated vendor pub/static pub/media app/etc -type d -exec chmod g+ws {} +
chmod u+x bin/magento

# Magento install
bin/magento setup:install \
--base-url="http://$DOMAIN/" \
--db-host="localhost" \
--db-name="$DB_NAME" \
--db-user="$DB_USER" \
--db-password="$DB_PASS" \
--admin-firstname="Admin" \
--admin-lastname="User" \
--admin-email="admin@$DOMAIN" \
--admin-user="admin" \
--admin-password="Admin123!" \
--language="en_US" \
--currency="USD" \
--timezone="Europe/Kyiv" \
--use-rewrites=1 \
--backend-frontname="admin"

# ------------------ NGINX ------------------
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name irelax.com.ua www.irelax.com.ua;
    set $MAGE_ROOT /var/www/irelax.com.ua;
    set $MAGE_MODE production;

    root $MAGE_ROOT/pub;

    index index.php;

    access_log /var/log/nginx/irelax_access.log;
    error_log /var/log/nginx/irelax_error.log;

    include $MAGE_ROOT/nginx.conf.sample;
}
EOF

ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# ------------------ Перезапуск служб ------------------
systemctl restart php8.2-fpm
systemctl restart nginx
systemctl restart redis-server
systemctl restart elasticsearch
systemctl restart varnish

echo "✅ Magento $MAGENTO_VERSION встановлено на http://$DOMAIN"
