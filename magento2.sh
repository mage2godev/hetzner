#!/bin/bash

set -e

# -------------------------------
# CONFIGURATION
# -------------------------------
MYSQL_ROOT_PASS="RootPass123!"
MYSQL_MAGENTO_DB="magento"
MYSQL_MAGENTO_USER="magento_user"
MYSQL_MAGENTO_PASS="Magent0UserPass!"
MAGENTO_VERSION="2.4.7"
MAGENTO_BASE_DIR="/var/www/magento2"
DOMAIN_NAME="irelax.com.ua"

# -------------------------------
# SWAP (для VPS < 4GB)
# -------------------------------
echo "Creating swap file..."
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# -------------------------------
# UPDATE SYSTEM
# -------------------------------
echo "Updating system..."
apt update && apt upgrade -y

# -------------------------------
# INSTALL PACKAGES
# -------------------------------
echo "Installing Apache, PHP, Redis, Varnish..."
apt install -y mariadb-server
apt install -y apt-transport-https ca-certificates gnupg
apt install -y apache2 php8.2 php8.2-fpm php8.2-cli php8.2-mysql \
  php8.2-xml php8.2-curl php8.2-gd php8.2-bcmath php8.2-intl \
  php8.2-soap php8.2-zip php8.2-mbstring php8.2-common php8.2-opcache \
  php8.2-readline unzip curl git redis-server varnish

# -------------------------------
# INSTALL COMPOSER
# -------------------------------
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# -------------------------------
# INSTALL Elasticsearch 7.x
# -------------------------------
echo "Installing Elasticsearch 7.x..."

wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor | tee /usr/share/keyrings/elasticsearch-keyring.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list

apt update && apt install -y elasticsearch

systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch

# -------------------------------
# CONFIGURE MYSQL
# -------------------------------
echo "Configuring MariaDB..."
mysql -u root <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
CREATE DATABASE ${MYSQL_MAGENTO_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '${MYSQL_MAGENTO_USER}'@'localhost' IDENTIFIED BY '${MYSQL_MAGENTO_PASS}';
GRANT ALL PRIVILEGES ON ${MYSQL_MAGENTO_DB}.* TO '${MYSQL_MAGENTO_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# -------------------------------
# CONFIGURE PHP
# -------------------------------
echo "Configuring PHP..."
sed -i 's/memory_limit = .*/memory_limit = 2G/' /etc/php/8.2/fpm/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' /etc/php/8.2/fpm/php.ini
sed -i 's/post_max_size = .*/post_max_size = 64M/' /etc/php/8.2/fpm/php.ini
sed -i 's/;date.timezone =.*/date.timezone = UTC/' /etc/php/8.2/fpm/php.ini

systemctl restart php8.2-fpm

# -------------------------------
# DOWNLOAD MAGENTO
# -------------------------------
echo "Downloading Magento ${MAGENTO_VERSION}..."
mkdir -p ${MAGENTO_BASE_DIR}
cd ${MAGENTO_BASE_DIR}

echo "Run: composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=${MAGENTO_VERSION}"
echo "Use your Magento Marketplace keys when prompted."
composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=${MAGENTO_VERSION} .

# -------------------------------
# SET PERMISSIONS
# -------------------------------
echo "Setting permissions..."
find var generated vendor pub/static pub/media app/etc -type f -exec chmod g+w {} +
find var generated vendor pub/static pub/media app/etc -type d -exec chmod g+ws {} +
chown -R www-data:www-data ${MAGENTO_BASE_DIR}

# -------------------------------
# CONFIGURE APACHE
# -------------------------------
echo "Configuring Apache VirtualHost..."
a2enmod rewrite proxy_fcgi setenvif
a2enconf php8.2-fpm

cat > /etc/apache2/sites-available/magento.conf <<EOL
<VirtualHost *:8080>
    ServerName ${DOMAIN_NAME}
    DocumentRoot ${MAGENTO_BASE_DIR}

    <Directory ${MAGENTO_BASE_DIR}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/magento_error.log
    CustomLog \${APACHE_LOG_DIR}/magento_access.log combined
</VirtualHost>
EOL

# -------------------------------
# CONFIGURE VARNISH
# -------------------------------
echo "Configuring Varnish..."
sed -i 's/.Port = "6081"/.Port = "80"/' /etc/varnish/default.vcl || true

cat > /etc/varnish/default.vcl <<EOL
vcl 4.0;

backend default {
    .host = "127.0.0.1";
    .port = "8080";
}

include "/etc/varnish/magento.vcl";
EOL

# Copy default VCL for Magento:
cat > /etc/varnish/magento.vcl <<EOL
# Basic Magento Varnish config
# You can generate optimized VCL in Magento Admin
vcl 4.0;

backend default {
    .host = "127.0.0.1";
    .port = "8080";
}
EOL

# Update systemd varnish port
sed -i 's/-a :6081/-a :80/' /etc/systemd/system/multi-user.target.wants/varnish.service || true

a2dissite 000-default.conf
a2ensite magento.conf

systemctl daemon-reload
systemctl restart apache2
systemctl restart varnish

# -------------------------------
# INSTALL MAGENTO
# -------------------------------
echo "Installing Magento..."
bin/magento setup:install \
  --base-url=http://${DOMAIN_NAME}/ \
  --db-host=localhost \
  --db-name=${MYSQL_MAGENTO_DB} \
  --db-user=${MYSQL_MAGENTO_USER} \
  --db-password=${MYSQL_MAGENTO_PASS} \
  --admin-firstname=Admin \
  --admin-lastname=User \
  --admin-email=admin@${DOMAIN_NAME} \
  --admin-user=admin \
  --admin-password=Admin123! \
  --language=en_US \
  --currency=USD \
  --timezone=UTC \
  --use-rewrites=1 \
  --search-engine=elasticsearch7 \
  --elasticsearch-host=localhost \
  --elasticsearch-port=9200 \
  --session-save=redis \
  --cache-backend=redis \
  --cache-backend-redis-server=127.0.0.1 \
  --cache-backend-redis-port=6379 \
  --page-cache=varnish \
  --page-cache-varnish-hosts=127.0.0.1:80

bin/magento deploy:mode:set production
bin/magento setup:upgrade
bin/magento cache:flush

echo "Magento ${MAGENTO_VERSION} with Apache + Redis + Varnish + Elasticsearch7 installed!"
echo "Open your site: http://${DOMAIN_NAME}"
