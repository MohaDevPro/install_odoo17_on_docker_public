#!/bin/bash

# Default IP address and subnet
DEFAULT_IP="192.168.0.20"
SUBNET="192.168."

# List of common ports to exclude
common_ports="80 8080"

# Function to check if an IP is in use
is_ip_in_use() {
    ping -c 1 -W 1 "$1" &> /dev/null
    return $?
}

# Check if a port is in use
port_in_use() {
    sudo netstat -tuln | grep -q ":$1 "
}

# Check if a port is a common port
is_common_port() {
    for port in $common_ports; do
        if [ "$1" -eq "$port" ]; then
            return 0
        fi
    done
    return 1
}

# Parameters
DESTINATION=$1
USER_PORT=${2:-}  # User-provided PORT or empty if not provided
USER_CHAT=${3:-}  # User-provided CHAT or empty if not provided

# Determine PORT and CHAT
if [[ -n $USER_PORT && -n $USER_CHAT ]]; then
    PORT=$USER_PORT
    CHAT=$USER_CHAT
else
    PORT=${USER_PORT:-10015}  # Default PORT is 10015 if not provided
    CHAT=$((PORT + 10000))  # CHAT is PORT + 10000

    # Find available PORT and CHAT if not provided
    while true; do
        if ! port_in_use "$PORT" && ! is_common_port "$PORT"; then
            # Check CHAT availability
            if ! port_in_use "$CHAT" && ! is_common_port "$CHAT"; then
                echo "Ports assigned: PORT=$PORT and CHAT=$CHAT"
                break
            else
                # Increment PORT and recalculate CHAT
                PORT=$((PORT + 1))
                CHAT=$((PORT + 10000))
            fi
        else
            # Increment PORT and recalculate CHAT
            PORT=$((PORT + 1))
            CHAT=$((PORT + 10000))
        fi
    done
fi

# Find an unused IP and assign it to IPADD
IPADD=""
for i in {0..3}; do
    for j in {1..254}; do
        IP="${SUBNET}${i}.${j}"

        # Skip the default IP and check if the IP is in use
        if [[ "$IP" != "$DEFAULT_IP" && ! $(is_ip_in_use "$IP") ]]; then
            IPADD="$IP"
            echo "Unused IP found: $IPADD"
            break 2  # Exit both loops after finding the first unused IP
        fi
    done
done

# Other parameters
PGADMIN=${4:-}  # Optionally provided PGADMIN
ODOO_VERSION=${5:-17}  # Default Odoo version is 17 if not provided

# You can add further logic here using $DESTINATION, $PORT, $CHAT, $PGADMIN, and $ODOO_VERSION
echo "Final Ports: PORT=$PORT, CHAT=$CHAT"

# Clone Odoo directory
git clone --depth=1 https://github.com/MohaDevPro/install_odoo17_on_docker_public.git "$DESTINATION"
rm -rf "$DESTINATION/.git"

# Set permissions
mkdir -p "$DESTINATION/postgresql"
sudo chmod -R 777 "$DESTINATION"

# Config
if grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf; then
    echo $(grep -F "fs.inotify.max_user_watches" /etc/sysctl.conf)
else
    echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Update ports in docker-compose.yml
sed -i "s/10015/$PORT/g" "$DESTINATION/docker-compose.yml"
sed -i "s/20015/$CHAT/g" "$DESTINATION/docker-compose.yml"
sed -i "s/5053/$PGADMIN/g" "$DESTINATION/docker-compose.yml"
sed -i "s/192.168.0.20/${IPADD}/g" "$DESTINATION/docker-compose.yml"


# Update Odoo version in image and replace 'odoo17' with 'odoo' + the provided version
sed -i "s|odoo:[0-9]\+|odoo:$ODOO_VERSION|g" "$DESTINATION/docker-compose.yml"
sed -i "s|odoo17|odoo$ODOO_VERSION|g" "$DESTINATION/docker-compose.yml"

# Update the Dockerfile for the Odoo version
DOCKERFILE="$DESTINATION/Dockerfile"
if [[ -f $DOCKERFILE ]]; then
    sed -i "s|FROM odoo:[0-9]\+|FROM odoo:$ODOO_VERSION|g" "$DOCKERFILE"
else
    echo "Dockerfile not found at $DOCKERFILE"
fi


# Run Odoo
docker compose -f "$DESTINATION/docker-compose.yml" up -d

echo "Started Odoo @ http://localhost:$PORT | Master Password: admin@1234 | Live chat port: $CHAT"
