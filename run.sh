#!/bin/bash
DESTINATION=$1
PORT=$2
CHAT=$3
PGADMIN=$4
ODOO_VERSION=${5:-17}  # Set default Odoo version to 17 if not provided

# Clone Odoo directory
git clone --depth=1 https://github.com/MohaDevPro/install_odoo17_on_docker_public.git $DESTINATION
rm -rf $DESTINATION/.git

# Set permissions
mkdir -p $DESTINATION/postgresql
sudo chmod -R 777 $DESTINATION

# Config
if grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf; then
    echo $(grep -F "fs.inotify.max_user_watches" /etc/sysctl.conf)
else
    echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Update ports in docker-compose.yml
sed -i "s/10015/$PORT/g" $DESTINATION/docker-compose.yml
sed -i "s/20015/$CHAT/g" $DESTINATION/docker-compose.yml
sed -i "s/5053/$PGADMIN/g" $DESTINATION/docker-compose.yml

# Update Odoo version
sed -i "s|odoo:[0-9]\+|odoo:$ODOO_VERSION|g" $DESTINATION/docker-compose.yml

# Run Odoo
docker compose -f $DESTINATION/docker-compose.yml up -d

echo "Started Odoo @ http://localhost:$PORT | Master Password: admin@1234 | Live chat port: $CHAT"
