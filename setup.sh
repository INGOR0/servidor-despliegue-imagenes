#!/bin/bash

###############################################
## SCRIPT HECHO POR IVÁN GARRIDO ROMERO PARA ##
## EL SERVIDOR DE DESPLIEGUE DE IMÁGENES DEL ##
##    INSTITUTO IES RAMÓN DEL VALLE-INCLÁN   ##
##    TODO CAMBIO AL SCRIPT ESTÁ PERMITIDO   ##
###############################################

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse como root."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------- Instalar iVentoy ------------- #

echo "Instalando iVentoy.."



# Descargar y extraer

IVENTOY_VERSION="1.0.21"

cd /opt
rm -rf iventoy
wget https://github.com/ventoy/PXE/releases/download/v${IVENTOY_VERSION}/iventoy-${IVENTOY_VERSION}-linux-free.tar.gz
tar -xzf iventoy-${IVENTOY_VERSION}-linux-free.tar.gz
mv iventoy-${IVENTOY_VERSION} iventoy
rm iventoy-${IVENTOY_VERSION}-linux-free.tar.gz



# Script de arranque y servicio

cp "$SCRIPT_DIR/iventoy-files/start_iventoy.sh" /usr/local/bin/start_iventoy.sh
chmod +x /usr/local/bin/start_iventoy.sh
cp "$SCRIPT_DIR/iventoy-files/iventoy.service" /etc/systemd/system/iventoy.service

cp $SCRIPT_DIR/iventoy-files/fake.iso /opt/iventoy/iso
cd /opt/iventoy
bash iventoy.sh -R start
echo ""
echo "Abre http://<IP>:26000 en tu navegador, activa el servidor PXE y pulsa ENTER para continuar..."
read -p ""

cd /opt/iventoy
bash iventoy.sh stop
systemctl daemon-reload
systemctl enable iventoy
systemctl restart iventoy

echo "iVentoy instalado y corriendo con éxito."



# ------------- Descargar Clonezilla ------------- #

echo "Descargando Clonezilla..."

CLONEZILLA_VERSION="3.3.1-35"
CLONEZILLA_ISO="clonezilla-live-$CLONEZILLA_VERSION-amd64.iso"
CLONEZILLA_URL="https://downloads.sourceforge.net/project/clonezilla/clonezilla_live_stable/$CLONEZILLA_VERSION/$CLONEZILLA_ISO"
CLONEZILLA_SHA256="ac4f88c8795a917e3d3fc1a3e52d095f35fe531d459cf853cd3e2c7731043fec"

mkdir -p /tmp/clonezilla-original
cd /tmp/clonezilla-original
wget "$CLONEZILLA_URL" -O "$CLONEZILLA_ISO"

echo "$CLONEZILLA_SHA256  $CLONEZILLA_ISO" | sha256sum -c --strict

echo "Clonezilla descargado y verificado con éxito."



# ------------- Instalar Samba------------- #

read -p "Usuario de Samba con permisos de escritura: " SAMBA_USER
read -sp "Contraseña de dicho usuario: " SAMBA_PASS
echo ""

SAMBA_DIR="/srv/samba"
SAMBA_SHARE_ISO="ISOs"
SAMBA_SHARE_CLONEZILLA="Clonezilla"
SAMBA_SHARE_RECURSOS_COMPARTIDOS="Recursos_Compartidos"

apt install samba -y

mkdir -p "$SAMBA_DIR"
[ -L "$SAMBA_DIR/$SAMBA_SHARE_ISO" ] || ln -s "/opt/iventoy/iso" "$SAMBA_DIR/$SAMBA_SHARE_ISO"
mkdir -p "$SAMBA_DIR/$SAMBA_SHARE_CLONEZILLA"
mkdir -p "$SAMBA_DIR/$SAMBA_SHARE_RECURSOS_COMPARTIDOS"

id "$SAMBA_USER" &>/dev/null || useradd -M -s /usr/sbin/nologin "$SAMBA_USER"
echo -e "$SAMBA_PASS\n$SAMBA_PASS" | smbpasswd -a -s "$SAMBA_USER"

chown -R "$SAMBA_USER:$SAMBA_USER" "$SAMBA_DIR/$SAMBA_SHARE_CLONEZILLA"
chown -R "$SAMBA_USER:$SAMBA_USER" "$SAMBA_DIR/$SAMBA_SHARE_RECURSOS_COMPARTIDOS"

id "anonimo" &>/dev/null || useradd -M -s /usr/sbin/nologin anonimo
echo -e "anonimo\nanonimo" | smbpasswd -a -s "anonimo"

sed -e "s|__SAMBA_DIR__|$SAMBA_DIR|g" \
    -e "s|__SAMBA_SHARE_ISO__|$SAMBA_SHARE_ISO|g" \
    -e "s|__SAMBA_SHARE_CLONEZILLA__|$SAMBA_SHARE_CLONEZILLA|g" \
    -e "s|__SAMBA_SHARE_RECURSOS_COMPARTIDOS__|$SAMBA_SHARE_RECURSOS_COMPARTIDOS|g" \
    -e "s|__SAMBA_USER__|$SAMBA_USER|g" \
    "$SCRIPT_DIR/samba-files/smb.conf" > /etc/samba/smb.conf

systemctl restart smbd



# wsdd para descubrimiento en Windows

apt install wsdd2 -y
systemctl enable wsdd2
systemctl start wsdd2

# avahi para descubrimiento en Linux y Mac

apt install avahi-daemon -y
systemctl enable avahi-daemon
systemctl start avahi-daemon



# ------------- Preparar Clonezilla ------------- #

read -p "IP del servidor (ej. 172.17.5.222): " SERVER_IP
echo "Preparando ISO de Clonezilla..."



# Montar la ISO y copiarla

WORK_DIR="/tmp/clonezilla-copiada"
ORIGINAL_CLONEZILLA_DIR="/mnt/clonezilla-original"

cd /tmp/clonezilla-original # Por si acaso
mkdir -p "$WORK_DIR"
mkdir -p "$ORIGINAL_CLONEZILLA_DIR"
mount -o loop "$CLONEZILLA_ISO" "$ORIGINAL_CLONEZILLA_DIR"
cp -r "$ORIGINAL_CLONEZILLA_DIR/." "$WORK_DIR"
umount "$ORIGINAL_CLONEZILLA_DIR"
chmod -R u+w "$WORK_DIR"



# Reemplazar placeholders en la plantilla y copiar a syslinux e isolinux

sed -e "s/__SERVER_IP__/$SERVER_IP/g" \
    -e "s/__SAMBA_USER__/$SAMBA_USER/g" \
    -e "s/__SAMBA_PASS__/$SAMBA_PASS/g" \
    "$SCRIPT_DIR/clonezilla-files/menu.cfg" > "$WORK_DIR/syslinux/syslinux.cfg"

cp "$WORK_DIR/syslinux/syslinux.cfg" "$WORK_DIR/syslinux/isolinux.cfg"

mkdir -p "$WORK_DIR/boot/grub"
sed -e "s/__SERVER_IP__/$SERVER_IP/g" \
    -e "s/__SAMBA_USER__/$SAMBA_USER/g" \
    -e "s/__SAMBA_PASS__/$SAMBA_PASS/g" \
    "$SCRIPT_DIR/clonezilla-files/grub.cfg" > "$WORK_DIR/boot/grub/grub.cfg"

    

# Reconstruir ISO

apt install xorriso -y

xorriso -as mkisofs \
    -r -J -joliet-long \
    -l \
    -isohybrid-mbr "$WORK_DIR/syslinux/isolinux.bin" \
    -partition_offset 16 \
    -A "Clonezilla Live" \
    -b syslinux/isolinux.bin \
    -c syslinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "/opt/iventoy/iso/clonezilla-custom.iso" \
    "$WORK_DIR"

rm -rf "$WORK_DIR"
rm -rf /tmp/clonezilla-original

echo "ISO de Clonezilla preparada con éxito."
rm /opt/iventoy/iso/fake.iso


# ------------- Instalar Webmin ------------- #

mkdir /tmp/webmin
cd /tmp/webmin
apt install curl -y
curl -o webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh
echo "y" | sh webmin-setup-repo.sh
apt-get install webmin --install-recommends -y
cd /root
rm -rf /tmp/webmin



# ------------- Instalar nginx ------------- #

apt install nginx -y

read -p "Dominio (ej. dployerz.com): " DOMAIN
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/CN=*.$DOMAIN" \
    -addext "subjectAltName=DNS:*.$DOMAIN,DNS:$DOMAIN"

sed "s|__DOMAIN__|$DOMAIN|g" \
    "$SCRIPT_DIR/nginx-files/portal.conf" > /etc/nginx/sites-available/portal.conf
    

cp -r "$SCRIPT_DIR/portal" /var/www/html
find /var/www/html/portal -type f -name "*.html" -exec sed -i "s|__DOMAIN__|$DOMAIN|g" {} \;
[ -L /etc/nginx/sites-enabled/portal.conf ] || ln -s /etc/nginx/sites-available/portal.conf /etc/nginx/sites-enabled

systemctl enable nginx
systemctl reload nginx

# ------------- Instalar sistema de login ------------- #

apt install nodejs mariadb-server npm -y

DB_USER="portal_user"
DB_PASS=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")

mysql -u root << EOF
CREATE DATABASE portal;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON portal.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
USE portal;
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('admin', 'user') DEFAULT 'user',
    status ENUM('active', 'inactive') DEFAULT 'active'
);
EOF

mkdir -p /opt/auth-server
cp "$SCRIPT_DIR/auth-server/package.json" /opt/auth-server
cd /opt/auth-server
npm install

read -sp "Contraseña para el usuario admin: " ADMIN_PASS
echo ""

ADMIN_HASH=$(ADMIN_PASS="$ADMIN_PASS" node -e "const bcrypt = require('bcrypt'); console.log(bcrypt.hashSync(process.env.ADMIN_PASS, 10))")
mysql << EOF
USE portal;
INSERT INTO users (username, password_hash, role, status) VALUES ('admin', '$ADMIN_HASH', 'admin', 'active');
EOF

SESSION_SECRET=$(node -e "console.log(require('crypto').randomBytes(64).toString('hex'))")

sed -e "s|__SESSION_SECRET__|$SESSION_SECRET|g" \
    -e "s|__DB_USER__|$DB_USER|g" \
    -e "s|__DB_PASS__|$DB_PASS|g" \
    -e "s|__DOMAIN__|$DOMAIN|g" \
    "$SCRIPT_DIR/auth-server/index.js" > /opt/auth-server/index.js

cp "$SCRIPT_DIR/auth-server/auth-server.service" /etc/systemd/system/auth-server.service
systemctl daemon-reload
systemctl enable auth-server
systemctl start auth-server


# ------------- UFW SEGURIDAD ------------- #

apt install ufw -y

ufw allow 22
ufw allow 80
ufw allow 443
ufw allow from 127.0.0.1 to any port 3000
ufw deny 10000
ufw deny 26000
ufw allow samba
ufw allow 16000 # IMPORTANTE MUCHISIMO IMPORTANTE
ufw allow 67/udp # DHCP NO IMPORTA PERO POR SI ACASO
ufw allow 68/udp # DHCP TAMBIÉN
ufw allow 69/udp # TFTP
ufw allow 5357/tcp
ufw allow 3702/udp # WSD for Windows
ufw allow 5353/udp # mDNS for Avahi (Linux/Mac)
ufw allow 10809 #iVentoy's NBD port 
ufw --force enable
