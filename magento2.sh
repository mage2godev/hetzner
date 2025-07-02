#!/bin/bash

set -e

# -------------------------------
# CONFIGURATION
# -------------------------------
MYSQL_ROOT_PASS="RootPass123!"
MYSQL_MAGENTO_DB="magento_drop"
MYSQL_MAGENTO_USER="magento_drop"
MYSQL_MAGENTO_PASS="Magent0DropPass!"
MAGENTO_VERSION="2.4.6-p9"
MAGENTO_BASE_DIR="/var/www/magento2"
DOMAIN_NAME="irelax.com.ua"

# -------------------------------
# SWAP (для VPS < 4GB)
# -------------------------------
echo "Checking swap..."
if swapon --show | grep -q '/swapfile'; then
  echo "Swap already exists, skipping creation."
else
  echo "Creating swap file..."
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# -------------------------------
# UPDATE SYSTEM
# -------------------------------
echo "Updating system..."
#apt update && apt upgrade -y

# -------------------------------
# BASE PACKAGES
# -------------------------------
echo "Installing base packages..."
apt install -y apt-transport-https ca-certificates gnupg lsb-release wget curl unzip git

# -------------------------------
# FIXED MySQL 8 INSTALL
# -------------------------------
echo "Installing MySQL 8..."
# Remove old conflicting sources if they exist
rm -f /etc/apt/sources.list.d/mysql.list
sed -i '/repo.mysql.com/d' /etc/apt/sources.list

# Add MySQL GPG key using a simpler approach
mkdir -p /etc/apt/keyrings
wget -qO - https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 | gpg --yes --dearmor -o /etc/apt/keyrings/mysql-archive-keyring.gpg

# Add MySQL repository with the correct signed-by format
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/mysql-archive-keyring.gpg] http://repo.mysql.com/apt/ubuntu/ $(lsb_release -sc) mysql-8.0" | tee /etc/apt/sources.list.d/mysql.list

apt update
DEBIAN_FRONTEND=noninteractive apt install -y mysql-server

# Start and enable MySQL
systemctl start mysql
systemctl enable mysql

# Configure MySQL for Magento
cat > /etc/mysql/conf.d/magento.cnf <<EOF
[mysqld]
innodb_buffer_pool_size = 1G
max_allowed_packet = 64M
innodb_file_per_table = 1
innodb_flush_method = O_DIRECT
innodb_log_file_size = 256M
default-authentication-plugin = mysql_native_password
EOF

systemctl restart mysql

# -------------------------------
# INSTALL PHP, Apache, Redis, Varnish
# -------------------------------
echo "Installing Apache, PHP, Redis, Varnish..."
apt install -y apache2 php8.2 php8.2-fpm php8.2-cli php8.2-mysql \
  php8.2-xml php8.2-curl php8.2-gd php8.2-bcmath php8.2-intl \
  php8.2-soap php8.2-zip php8.2-mbstring php8.2-common php8.2-opcache \
  php8.2-readline redis-server varnish

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
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list

apt update && apt install -y elasticsearch

systemctl enable elasticsearch
systemctl start elasticsearch

# -------------------------------
# CONFIGURE MYSQL DATABASE
# -------------------------------
echo "Configuring MySQL..."
mysql -u root <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
CREATE DATABASE ${MYSQL_MAGENTO_DB};
ALTER DATABASE ${MYSQL_MAGENTO_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '${MYSQL_MAGENTO_USER}'@'localhost' IDENTIFIED BY '${MYSQL_MAGENTO_PASS}';
GRANT ALL PRIVILEGES ON ${MYSQL_MAGENTO_DB}.* TO '${MYSQL_MAGENTO_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# -------------------------------
# CONFIGURE PHP
# -------------------------------
echo "Configuring PHP..."
sed -i 's/memory_limit = .*/memory_limit = 4G/' /etc/php/8.2/fpm/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' /etc/php/8.2/fpm/php.ini
sed -i 's/post_max_size = .*/post_max_size = 64M/' /etc/php/8.2/fpm/php.ini
sed -i 's/;date.timezone =.*/date.timezone = UTC/' /etc/php/8.2/fpm/php.ini

systemctl restart php8.2-fpm

# -------------------------------
# PREPARE MAGENTO DIR
# -------------------------------
echo "Preparing Magento directory..."
mkdir -p ${MAGENTO_BASE_DIR}
cd ${MAGENTO_BASE_DIR}

# -------------------------------
# SET PERMISSIONS
# -------------------------------
echo "Setting permissions..."
mkdir -p var generated vendor pub/static pub/media app/etc
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

cat > /etc/varnish/magento.vcl <<EOL
vcl 4.0;

backend default {
    .host = "127.0.0.1";
    .port = "8080";
}
EOL

sed -i 's/-a :6081/-a :80/' /etc/systemd/system/multi-user.target.wants/varnish.service || true

a2dissite 000-default.conf
a2ensite magento.conf

systemctl daemon-reload
systemctl restart apache2
systemctl restart varnish

# -------------------------------
# DONE
# -------------------------------
echo "Magento ${MAGENTO_VERSION} with Apache + Redis + Varnish + Elasticsearch7 installed!"
echo "Open your site: http://${DOMAIN_NAME}"
