#!/bin/bash

apt install -y p7zip-full

useradd -r -M -d /srv/mysqldumper -s /bin/bash mysqldumper

touch /srv/mysqldumper/my.cnf
chmod 640 /srv/mysqldumper/my.cnf

chown -R mysqldumper:mysqldumper /srv/mysqldumper

mkdir /var/mysqldumps
chown -R mysqldumper:mysqldumper /var/mysqldumps

echo "#* * * * * mysqldumper /srv/mysqldumper/mysqldump.sh <backup-profile-name>" > /etc/cron.d/mysqldump
