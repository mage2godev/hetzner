#!/bin/bash

set -e

# -------------------------------
# CONFIGURATION
# -------------------------------
MYSQL_ROOT_PASS="RootPass123!"
MYSQL_MAGENTO_DB="magento_db"
MYSQL_MAGENTO_USER="magento_user"
MYSQL_MAGENTO_PASS="Magent0Pass123!"
MAGENTO_VERSION="2.4.6-p9"
MAGENTO_BASE_DIR="/var/www/magento"
DOMAIN_NAME="irelax.com.ua"
ADMIN_USER="admin"
ADMIN_PASS="AdminPass123!"
ADMIN_EMAIL="admin@${DOMAIN_NAME}"

# -------------------------------
# CREATE SWAP (for smaller servers)
# -------------------------------
echo "Setting up Swap..."
if ! swapon --show | grep -q '/swapfile'; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# -------------------------------
# SYSTEM UPDATE
# -------------------------------
echo "Updating System..."
apt update && apt upgrade -y

# -------------------------------
# INSTALL BASE PACKAGES
# -------------------------------
echo "Installing base packages..."
apt install -y \
    apt-transport-https ca-certificates gnupg lsb-release software-properties-common unzip wget curl git \
    apache2 php8.2 php8.2-fpm php8.2-cli php8.2-mysql php8.2-xml php8.2-curl php8.2-gd php8.2-bcmath php8.2-intl \
    php8.2-soap php8.2-zip php8.2-mbstring php8.2-common php8.2-opcache redis-server varnish mysql-server

# Fix PHP configurations:
sed -i 's/memory_limit = .*/memory_limit = 4G/' /etc/php/8.2/fpm/php.ini
sed -i 's/;date.timezone =.*/date.timezone = UTC/' /etc/php/8.2/fpm/php.ini

# -------------------------------
# MYSQL CONFIGURATION
# -------------------------------
echo "Configuring MySQL..."
mysql -uroot <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
CREATE DATABASE ${MYSQL_MAGENTO_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '${MYSQL_MAGENTO_USER}'@'localhost' IDENTIFIED BY '${MYSQL_MAGENTO_PASS}';
GRANT ALL PRIVILEGES ON ${MYSQL_MAGENTO_DB}.* TO '${MYSQL_MAGENTO_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

cat > /etc/mysql/conf.d/magento.cnf <<EOL
[mysqld]
innodb_buffer_pool_size = 1G
max_allowed_packet = 64M
innodb_log_file_size = 128M
EOL
systemctl restart mysql

# -------------------------------
# INSTALL AND CONFIGURE ELASTICSEARCH
# -------------------------------
echo "Installing Elasticsearch 7.x..."
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor > /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list
apt update && apt install -y elasticsearch
systemctl enable elasticsearch && systemctl start elasticsearch

# -------------------------------
# SETUP MAGENTO PROJECT
# -------------------------------
echo "Setting up Magento in ${MAGENTO_BASE_DIR}..."
mkdir -p ${MAGENTO_BASE_DIR}
chown -R www-data:www-data ${MAGENTO_BASE_DIR}

cd ${MAGENTO_BASE_DIR}
composer create-project --repository=https://repo.magento.com/ magento/project-community-edition=${MAGENTO_VERSION} .

php bin/magento setup:install \
    --base-url=http://${DOMAIN_NAME} \
    --db-host=localhost \
    --db-name=${MYSQL_MAGENTO_DB} \
    --db-user=${MYSQL_MAGENTO_USER} \
    --db-password=${MYSQL_MAGENTO_PASS} \
    --admin-firstname=admin \
    --admin-lastname=admin \
    --admin-email=${ADMIN_EMAIL} \
    --admin-user=${ADMIN_USER} \
    --admin-password=${ADMIN_PASS} \
    --language=en_US \
    --currency=USD \
    --timezone=UTC \
    --use-rewrites=1

# -------------------------------
# CONFIGURE VARNISH
# -------------------------------
echo "Configuring Varnish..."
cat > /etc/systemd/system/varnish.service.d/customexec.conf <<EOL
[Service]
ExecStart=
ExecStart=/usr/sbin/varnishd -a :80 \
    -T localhost:6082 \
    -f ${MAGENTO_BASE_DIR}/var/default.vcl \
    -s malloc,256m
EOL

a2dissite 000-default && a2enmod proxy_fcgi setenvif
systemctl daemon-reload && systemctl restart varnish apache2

echo "Magento ${MAGENTO_VERSION} ready at: http://${DOMAIN_NAME}/"
echo "Admin Panel: http://${DOMAIN_NAME}/admin (User:${ADMIN_USER}, Pass:${ADMIN_PASS})"
