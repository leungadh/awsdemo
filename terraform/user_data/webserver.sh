#!/bin/bash
# Web server cloud-init: Apache + PHP + MySQL + DVWA
# DVWA (Damn Vulnerable Web Application) provides realistic attack targets:
#   SQL injection, brute force, command injection, XSS
# Runs automatically on first boot (~5-7 minutes)
# Check status: sudo cloud-init status --wait

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ── System packages ───────────────────────────────────────────────────────────
apt-get update -y
apt-get install -y \
  apache2 \
  php \
  php-mysqli \
  php-gd \
  libapache2-mod-php \
  mysql-server \
  git \
  curl

# ── Enable Apache rewrite module ──────────────────────────────────────────────
a2enmod rewrite
a2enmod headers

# ── MySQL setup ───────────────────────────────────────────────────────────────
systemctl start mysql
systemctl enable mysql

mysql --user=root <<'MYSQL'
CREATE DATABASE IF NOT EXISTS dvwa;
CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY 'p@ssw0rd';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';
FLUSH PRIVILEGES;
MYSQL

# ── DVWA installation ─────────────────────────────────────────────────────────
cd /var/www/html
git clone --depth=1 https://github.com/digininja/DVWA.git dvwa

# Configure DVWA database credentials
cp dvwa/config/config.inc.php.dist dvwa/config/config.inc.php
sed -i "s/\$_DVWA\[ 'db_server' \]   = '127.0.0.1'/_DVWA[ 'db_server' ]   = '127.0.0.1'/" dvwa/config/config.inc.php
sed -i "s/p@ssw0rd/p@ssw0rd/" dvwa/config/config.inc.php  # already matches

# Set security level to low (makes SQLi and other attacks straightforward)
sed -i "s/\$_DVWA\[ 'default_security_level' \] = 'impossible'/\$_DVWA[ 'default_security_level' ] = 'low'/" dvwa/config/config.inc.php

# Permissions
chown -R www-data:www-data /var/www/html/dvwa
chmod -R 755 /var/www/html/dvwa
chmod 777 /var/www/html/dvwa/hackable/uploads
chmod 777 /var/www/html/dvwa/config

# ── Apache virtual host ───────────────────────────────────────────────────────
cat > /etc/apache2/conf-available/dvwa.conf <<'APACHE'
<Directory /var/www/html/dvwa>
    AllowOverride All
    Require all granted
</Directory>
APACHE
a2enconf dvwa

# ── Landing page ──────────────────────────────────────────────────────────────
cat > /var/www/html/index.html <<'HTML'
<!DOCTYPE html>
<html>
<head><title>Demo Web Server</title></head>
<body>
  <h1>Juniper vSRX Demo — Target Web Server</h1>
  <p>Server IP: 10.0.2.100</p>
  <ul>
    <li><a href="/dvwa/">DVWA (Damn Vulnerable Web App)</a></li>
    <li>Default credentials: admin / password</li>
  </ul>
</body>
</html>
HTML

# ── Restart Apache ────────────────────────────────────────────────────────────
systemctl restart apache2
systemctl enable apache2

echo "Web server setup complete" >> /var/log/demo-setup.log
