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

echo "=== [1] System Update ==="
apt update && apt upgrade -y

echo "=== [2] Install Basics ==="
apt install -y software-properties-common curl wget git unzip zip

echo "=== [3] Install PHP 8.1 ==="
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y php8.1 php8.1-{cli,fpm,common,mbstring,xml,gd,curl,mysql,bcmath,intl,zip,soap}

echo "=== [4] Install Composer 2.2 ==="
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer --version=2.2
rm composer-setup.php

echo "=== [5] Install MariaDB 10.5 ==="
apt install -y mariadb-server mariadb-client

mysql_secure_installation <<EOF

y
n
y
y
y
EOF

mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "=== [6] Install Elasticsearch 7.17 ==="
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
apt install -y apt-transport-https
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-7.x.list
apt update && apt install -y elasticsearch
systemctl enable elasticsearch
systemctl start elasticsearch

echo "=== [7] Install Redis ==="
apt install -y redis-server
systemctl enable redis-server
systemctl start redis-server

echo "=== [8] Install Varnish ==="
apt install -y varnish

echo "=== [9] Install Memcached ==="
apt install -y memcached
systemctl enable memcached
systemctl start memcached

echo "=== [10] Install NGINX ==="
apt install -y nginx

echo "=== [11] Install Certbot ==="
apt install -y certbot python3-certbot-nginx

echo "=== [12] Install Magento 2 ==="
mkdir -p $MAGENTO_DIR
cd $MAGENTO_DIR

# Встановлюємо Magento Open Source
composer config --global http-basic.repo.magento.com c5c73502f26b15c3d929a481280c862f 06f86d7b8cc8e508fd2878af817b9ba5
composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=2.4.6-p9 .

# Зробимо власника www-data
chown -R www-data:www-data $MAGENTO_DIR

echo "=== [13] Magento Setup Install ==="
sudo -u www-data php bin/magento setup:install \
--base-url=https://$DOMAIN \
--db-host=localhost \
--db-name=$DB_NAME \
--db-user=$DB_USER \
--db-password=$DB_PASS \
--backend-frontname=admin \
--admin-firstname=Admin \
--admin-lastname=User \
--admin-email=admin@$DOMAIN \
--admin-user=admin \
--admin-password=Admin123! \
--language=en_US \
--currency=USD \
--timezone=UTC \
--use-rewrites=1 \
--search-engine=elasticsearch7 \
--elasticsearch-host=localhost

echo "=== [14] Generate NGINX Config ==="
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    root $MAGENTO_DIR/pub;
    index index.php;

    access_log /var/log/nginx/$DOMAIN-access.log;
    error_log /var/log/nginx/$DOMAIN-error.log;

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
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

echo "=== [15] Obtain SSL ==="
certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

echo "=== [16] Force HTTPS Redirect ==="
sed -i '/server_name/a \    return 301 https://$host$request_uri;' /etc/nginx/sites-available/$DOMAIN

nginx -t && systemctl reload nginx

echo "=== [17] Done! ==="
echo "Magento 2 доступний на: https://$DOMAIN"
