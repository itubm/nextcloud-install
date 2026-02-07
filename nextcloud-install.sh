#!/bin/bash
# ==========================
# Proxmox + Ubuntu 22.04 + Nextcloud Auto Install
# ==========================

# CONFIG
VMID=110                     # ID VM, sesuaikan jika perlu
VM_NAME="nextcloud"
ISO_PATH="local:iso/ubuntu-22.04-live-server-amd64.iso"
BRIDGE="vmbr0"
IP_ADDR="192.168.100.15/24"
GATEWAY="192.168.100.2"
DNS="192.168.100.2"
RAM=4096
CPU=2
DISK=40G
PASSWORD="st412wow"      # root password Ubuntu
DB_NAME="nextcloud"
DB_USER="localhost"
DB_PASSWORD="localhost"
TRUSTED_DOMAINS=("192.168.100.15" "nextcloud.ubm.co.id")

# ==========================
# 1. Create VM
# ==========================
qm create $VMID --name $VM_NAME --memory $RAM --cores $CPU --net0 virtio,bridge=$BRIDGE \
  --ostype l26 --bootdisk scsi0 --scsihw virtio-scsi-pci --ide2 $ISO_PATH,media=cdrom \
  --serial0 socket --vga serial0 --agent 1

qm set $VMID --scsi0 local-lvm:$DISK

echo "VM $VM_NAME with ID $VMID created. Start the VM and continue installation manually via console."
echo "Ubuntu root password will be set to $PASSWORD"

# ==========================
# 2. Instructions for user
# ==========================
echo "Please complete Ubuntu 22.04 installation via Proxmox console:"
echo "- Set root password: $PASSWORD"
echo "- Configure static IP: $IP_ADDR with gateway $GATEWAY and DNS $DNS"
echo "- Install OpenSSH server"

echo "After OS installation and reboot, run the following commands inside the VM to install Nextcloud:"

cat <<'EOF'

# ==========================
# INSIDE THE VM
# ==========================

# Update system
sudo apt update && sudo apt upgrade -y

# Install packages
sudo apt install -y nginx mariadb-server php8.2-fpm php8.2-mysql php8.2-gd php8.2-curl php8.2-mbstring \
php8.2-intl php8.2-bcmath php8.2-gmp php8.2-xml php8.2-zip unzip wget curl

# Setup MariaDB
sudo mysql -e "CREATE DATABASE nextcloud;"
sudo mysql -e "CREATE USER 'localhost'@'%' IDENTIFIED BY 'localhost';"
sudo mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'localhost'@'%';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Download Nextcloud
cd /var/www/
sudo wget https://download.nextcloud.com/server/releases/nextcloud-28.0.11.zip
sudo unzip nextcloud-28.0.11.zip
sudo chown -R www-data:www-data nextcloud
sudo chmod -R 750 nextcloud

# Nginx configuration
sudo tee /etc/nginx/sites-available/nextcloud > /dev/null <<'NGXCONF'
server {
    listen 80;
    server_name _;

    root /var/www/nextcloud;
    index index.php index.html;

    client_max_body_size 512M;
    fastcgi_buffers 64 4K;

    set_real_ip_from 0.0.0.0/0;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;

    location / {
        try_files $uri $uri/ /index.php$request_uri;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_param HTTPS on;
        fastcgi_param HTTP_X_FORWARDED_PROTO https;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGXCONF

sudo ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo systemctl restart nginx
sudo systemctl enable nginx
sudo systemctl restart php8.2-fpm
sudo systemctl enable php8.2-fpm

# Setup Nextcloud config.php
sudo tee /var/www/nextcloud/config/config.php > /dev/null <<CONFIG
<?php
\$CONFIG = array (
  'trusted_domains' => array (
EOF

for domain in "${TRUSTED_DOMAINS[@]}"; do
    echo "    0 => '$domain'," | sudo tee -a /var/www/nextcloud/config/config.php
done

cat <<'CONFIG'
  ),
  'datadirectory' => '/var/www/nextcloud/data',
  'dbtype' => 'mysql',
  'version' => '28.0.11.1',
  'instanceid' => 'ocbhz1odqwyk',
  'passwordsalt' => 'nxr51Dq8wcU8iajUx6HMxm2pooYf/j',
  'secret' => 'jVD1pTsiOoUzifqXpukCgPhrSKit8qG//B1VdkcdxnfJlY/2',
  'overwrite.cli.url' => 'https://192.168.100.15',
  'dbname' => 'nextcloud',
  'dbhost' => 'localhost',
  'dbport' => '',
  'dbtableprefix' => 'oc_',
  'mysql.utf8mb4' => true,
  'dbuser' => 'localhost',
  'dbpassword' => 'localhost',
  'installed' => true,
);
CONFIG

sudo chown -R www-data:www-data /var/www/nextcloud
sudo chmod -R 750 /var/www/nextcloud

echo "Nextcloud installation completed. Access via http://192.168.100.15"

EOF

