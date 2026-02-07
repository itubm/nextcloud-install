#!/bin/bash
# Nextcloud 28 Full Install (Shell Only)
# GitHub-ready version
# Run as root
set -euo pipefail

# -------------------------
# Variables (ubah sesuai kebutuhan)
# -------------------------
DB_NAME="nextcloud"
DB_USER="localhost"
DB_PASS="localhost"
NEXTCLOUD_VERSION="28.0.11"
NEXTCLOUD_INSTANCEID="ocbhz1odqwyk"
TRUSTED_IP="192.168.100.15"
TRUSTED_DOMAIN="nextcloud.ubm.co.id"

# -------------------------
# 1️⃣ Update & install basics
# -------------------------
apt update && apt upgrade -y
apt install -y sudo curl wget gnupg lsb-release unzip ufw software-properties-common

# -------------------------
# 2️⃣ Install NGINX, PHP, MariaDB
# -------------------------
apt install -y nginx mariadb-server mariadb-client \
php8.2-fpm php8.2-mysql php8.2-gd php8.2-curl php8.2-mbstring php8.2-intl \
php8.2-bcmath php8.2-zip php8.2-imagick php8.2-xml php8.2-gmp php8.2-apcu php8.2-redis

systemctl enable --now nginx
systemctl enable --now php8.2-fpm
systemctl enable --now mariadb

# -------------------------
# 3️⃣ Setup MariaDB
# -------------------------
mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EXIT;
MYSQL_SCRIPT

sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl restart mariadb

# -------------------------
# 4️⃣ Download & setup Nextcloud
# -------------------------
cd /var/www
wget https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.zip
unzip nextcloud-${NEXTCLOUD_VERSION}.zip
chown -R www-data:www-data nextcloud
chmod -R 750 nextcloud

mkdir -p /var/www/nextcloud/data /var/www/nextcloud/apps
chown -R www-data:www-data /var/www/nextcloud/data /var/www/nextcloud/apps

# -------------------------
# 5️⃣ Setup NGINX server block
# -------------------------
cat >/etc/nginx/sites-available/nextcloud <<EOF
server {
    listen 80;
    server_name $TRUSTED_IP $TRUSTED_DOMAIN;

    root /var/www/nextcloud;
    index index.php index.html;

    client_max_body_size 512M;
    fastcgi_buffers 64 4K;

    set_real_ip_from 0.0.0.0/0;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;

    location / {
        try_files \$uri \$uri/ /index.php\$request_uri;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_param HTTPS off;
        fastcgi_read_timeout 360;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# -------------------------
# 6️⃣ PHP-FPM tuning
# -------------------------
PHP_POOL="/etc/php/8.2/fpm/pool.d/www.conf"
sed -i "s/^;pm.max_children.*/pm.max_children = 50/" $PHP_POOL
sed -i "s/^;pm.start_servers.*/pm.start_servers = 5/" $PHP_POOL
sed -i "s/^;pm.min_spare_servers.*/pm.min_spare_servers = 5/" $PHP_POOL
sed -i "s/^;pm.max_spare_servers.*/pm.max_spare_servers = 35/" $PHP_POOL
sed -i "s/^;request_terminate_timeout.*/request_terminate_timeout = 360/" $PHP_POOL
systemctl restart php8.2-fpm

PHP_INI="/etc/php/8.2/fpm/php.ini"
sed -i "s/^upload_max_filesize.*/upload_max_filesize = 512M/" $PHP_INI
sed -i "s/^post_max_size.*/post_max_size = 512M/" $PHP_INI
sed -i "s/^memory_limit.*/memory_limit = 512M/" $PHP_INI
sed -i "s/^max_execution_time.*/max_execution_time = 360/" $PHP_INI
systemctl restart php8.2-fpm

# -------------------------
# 7️⃣ Setup Nextcloud config.php
# -------------------------
cp config/nextcloud-config.php.template /var/www/nextcloud/config/config.php
sed -i "s|__TRUSTED_IP__|$TRUSTED_IP|g" /var/www/nextcloud/config/config.php
sed -i "s|__TRUSTED_DOMAIN__|$TRUSTED_DOMAIN|g" /var/www/nextcloud/config/config.php
sed -i "s|__DB_NAME__|$DB_NAME|g" /var/www/nextcloud/config/config.php
sed -i "s|__DB_USER__|$DB_USER|g" /var/www/nextcloud/config/config.php
sed -i "s|__DB_PASS__|$DB_PASS|g" /var/www/nextcloud/config/config.php
chown -R www-data:www-data /var/www/nextcloud

# -------------------------
# 8️⃣ Firewall
# -------------------------
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "✅ Nextcloud 28 GitHub-ready install selesai!"
echo "Akses via IP: http://$TRUSTED_IP"
