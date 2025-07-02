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

# ------------------ Оновлення системи ------------------
apt update && apt upgrade -y

# ------------------ Встановлення базових пакунків ------------------
apt install -y nginx mysql-server redis-server git curl unzip software-properties-common

# ------------------ MySQL ------------------
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASS'; FLUSH PRIVILEGES;"
mysql -u root -p$MYSQL_ROOT_PASS -e "CREATE DATABASE $DB_NAME;"
mysql -u root -p$MYSQL_ROOT_PASS -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -u root -p$MYSQL_ROOT_PASS -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

# ------------------ PHP 8.2 ------------------
add-apt-repository ppa:ondrej/php -y && apt update
apt install -y php8.2 php8.2-cli php8.2-fpm php8.2-mysql php8.2-curl php8.2-xml php8.2-mbstring php8.2-bcmath php8.2-soap php8.2-intl php8.2-zip php8.2-gd php8.2-readline php8.2-opcache

# ------------------ Composer 2.2 ------------------
EXPECTED_VERSION="2.2"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --version=$EXPECTED_VERSION --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

# ------------------ Elasticsearch ------------------
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /etc/apt/trusted.gpg.d/elastic.gpg
echo "deb https://artifacts.elastic.co/packages/$ES_VERSION/apt stable main" | tee /etc/apt/sources.list.d/elastic-$ES_VERSION.list
apt update && apt install elasticsearch -y
systemctl enable elasticsearch
systemctl start elasticsearch

# ------------------ Varnish ------------------
apt install -y varnish

# ------------------ Magento ------------------
mkdir -p $MAGENTO_DIR
cd $MAGENTO_DIR

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
    server_name $DOMAIN www.$DOMAIN;
    set \$MAGE_ROOT $MAGENTO_DIR;
    include /var/www/$DOMAIN/nginx.conf.sample;
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
