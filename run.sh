#!/bin/bash

# Default IP address and subnet
DEFAULT_IP="172.25.0.1"  # Update the default IP address
SUBNET="172.25."          # Update the subnet

# List of common ports to exclude
common_ports="80 8080"

# Function to check if an IP is in use within the specified Docker network
is_ip_in_use() {
  local ip="$1"
  docker network inspect odoo-network | grep -q "\"IPv4Address\": \"${ip}/"
  if [[ $? -eq 0 ]]; then
    echo "IP address ${ip} is in use."
    return 0  # Return 1 if IP is in use
  else
    echo "IP address ${ip} is NOT in use."
    return 1  # Return 0 if IP is not in use
  fi
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

# Function to find an unused IP address
find_unused_ip() {
    local ip_var_name="$1"  # Name of the variable to store the IP
    local exclude_ip="$2"    # IP address to exclude

    for i in {0..255}; do
        for j in {1..254}; do
            local IP="${SUBNET}${i}.${j}"
            echo "Finding unused IP: $IP"

            # Skip the default IP and the excluded IP, and check if the IP is in use
            if [[ "$IP" != "$DEFAULT_IP" && "$IP" != "$exclude_ip" && $(is_ip_in_use "$IP") && $? -eq 1 ]]; then
                eval "$ip_var_name=\"$IP\""  # Assign the found IP to the variable
                echo "Unused IP found: $IP"
                return 0  # Exit the function successfully
            fi
        done
    done
    return 1  # No unused IP found
}

# Function to get full paths for addons
get_addons_paths() {
    local base_addon_path="/mnt/extra-addons"
    local all_subdirs=()
    local addon_paths=()

    # Get all subdirectories from /opt/AdwatModules
    while IFS= read -r -d '' subdir; do
        all_subdirs+=("$subdir")
    done < <(find /opt/AdwatModules -mindepth 1 -maxdepth 1 -type d -print0)

    # Check if any subdirectory arguments were provided
    if [[ $# -eq 0 ]]; then
        # No specific subdir arguments provided, use all subdirectories
        for subdir in "${all_subdirs[@]}"; do
            dir_name=$(basename "$subdir")
            addon_paths+=("$base_addon_path/$dir_name")
        done
    else
        # Loop through the provided arguments
        for arg in "$@"; do
            if [[ $arg == -* ]]; then
                # Remove the leading '-' to get the directory name
                dir_name="${arg:1}"
                # Construct the full path if the directory exists
                full_path="/opt/AdwatModules/$dir_name"
                if [[ -d $full_path ]]; then
                    addon_paths+=("$base_addon_path/$dir_name")
                fi
            fi
        done
    fi

    # Join the paths with commas
    IFS=',' # Set the delimiter to comma
    echo "${addon_paths[*]}"
}



# Parameters
NAME=$1
USER_PORT=${2:-}  # User-provided PORT or empty if not provided
USER_CHAT=${3:-}  # User-provided CHAT or empty if not provided

# Initialize PORT and CHAT
PORT=""
CHAT=""

# Determine PORT and CHAT based on user input
if [[ -n $USER_PORT && $USER_PORT != -* && $USER_PORT =~ ^[0-9]+$ ]]; then
    PORT=$USER_PORT
fi

if [[ -n $USER_CHAT && $USER_CHAT != -* && $USER_CHAT =~ ^[0-9]+$ ]]; then
    CHAT=$USER_CHAT
fi

# Find available PORT and CHAT only if the user inputs are invalid
if [[ -z $PORT || -z $CHAT ]]; then
    # Start searching from a base port if not set
    if [[ -z $PORT ]]; then
        PORT=10015  # Starting point
    fi
    
    while true; do
        if ! port_in_use "$PORT" && ! is_common_port "$PORT"; then
            # Check CHAT availability
            CHAT=$((PORT + 10000))
            if ! port_in_use "$CHAT" && ! is_common_port "$CHAT"; then
                echo "Ports assigned: PORT=$PORT and CHAT=$CHAT"
                break
            fi
        fi
        # Increment PORT
        PORT=$((PORT + 1))
    done
else
    echo "Using provided ports: PORT=$PORT and CHAT=$CHAT"
fi

# Find an unused IP for PG_IPADD first
# PG_IPADD=""
# find_unused_ip "PG_IPADD" "" 

# Now find an unused IP for IPADD
IPADD=""
# find_unused_ip "IPADD" "$PG_IPADD"
find_unused_ip "IPADD" ""

# Other parameters
ODOO_VERSION=${4:-17}  # Default Odoo version is 17 if not provided

# You can add further logic here using $NAME, $PORT, $CHAT, and $ODOO_VERSION
echo "Final Ports: PORT=$PORT, CHAT=$CHAT"

# Clone Odoo directory
git clone --depth=1 https://github.com/MohaDevPro/install_odoo17_on_docker_public.git "$NAME" || { echo "Failed to clone repository"; exit 1; }
rm -rf "$NAME/.git"

# Set permissions
mkdir -p "$NAME/postgresql"
# mkdir -p "$NAME/odoo-data"
# ln -s /opt/AdwatModules/* "$NAME/addons"
# cp -r /opt/AdwatModules/* "$NAME/addons"

# Set permissions
sudo chmod -R 777 "$NAME" 

# Collect only the arguments that start with '-'
SUBDIR_ARGS=()
for arg in "$@"; do
    if [[ $arg == -* ]]; then
        SUBDIR_ARGS+=("$arg")
    fi
done

# Join the paths with commas
ADDONS_PATH=$(get_addons_paths "${SUBDIR_ARGS[@]}")

# Example output
echo "addons_path = $ADDONS_PATH"

ODOO_CONF="$NAME/etc/odoo.conf"

if [[ -f "$ODOO_CONF" ]]; then
    # Append to the addons_path line
    sed -i "/^addons_path/c\addons_path = /mnt/extra-addons, $ADDONS_PATH" "$ODOO_CONF"
else
    echo "Odoo configuration file not found: $ODOO_CONF"
fi

# Config
if grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf; then
    echo $(grep -F "fs.inotify.max_user_watches" /etc/sysctl.conf)
else
    echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Update ports in docker-compose.yml
sed -i "s/odoo_name/$NAME/g" "$NAME/docker-compose.yml"
sed -i "s/10015/$PORT/g" "$NAME/docker-compose.yml"
sed -i "s/20015/$CHAT/g" "$NAME/docker-compose.yml"
sed -i "s/172.25.0.2/${PG_IPADD}/g" "$NAME/docker-compose.yml"
sed -i "s/172.25.0.3/${IPADD}/g" "$NAME/docker-compose.yml"

# Update Odoo version in image and replace 'odoo17' with 'odoo' + the provided version
sed -i "s|odoo:[0-9]\+|odoo:$ODOO_VERSION|g" "$NAME/docker-compose.yml"
sed -i "s|odoo17|odoo$ODOO_VERSION|g" "$NAME/docker-compose.yml"

# # Update the Dockerfile for the Odoo version
# DOCKERFILE="$NAME/Dockerfile"
# if [[ -f $DOCKERFILE ]]; then
#     sed -i "s|FROM odoo:[0-9]\+|FROM odoo:$ODOO_VERSION|g" "$DOCKERFILE"
# else
#     echo "Dockerfile not found at $DOCKERFILE"
# fi

# Run Odoo
docker compose -f "$NAME/docker-compose.yml" up -d
sudo chmod -R 777 "$NAME/postgresql" 

echo "Started Odoo @ http://localhost:$PORT | Master Password: admin@1234 | Live chat port: $CHAT"



#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
INSTALL_NGINX="True"
NAME_URL=$(echo "$NAME" | sed 's/_/-/g')
WEBSITE_NAME="succestools.com"
ENABLE_SSL="True"
ADMIN_EMAIL="adwat.alnjah@gmail.com"
# Get the IP address
ip4_address=$(hostname -I | awk '{print $1}')
if [ $INSTALL_NGINX = "True" ]; then
  echo -e "\n---- Installing and setting up Nginx ----"
  sudo apt install nginx -y
  cat <<EOF > /etc/nginx/sites-available/$NAME
  server {
  listen 80;
  server_name $NAME_URL.$WEBSITE_NAME;

  # Redirect to HTTPS
  return 301 https://\$host\$request_uri;
  } # managed by Certbot

  server {
      listen 443 ssl;
      server_name $NAME_URL.$WEBSITE_NAME;

      # SSL Certificate Configuration
      ssl_certificate /etc/letsencrypt/live/$NAME_URL.$WEBSITE_NAME/fullchain.pem;
      ssl_certificate_key /etc/letsencrypt/live/$NAME_URL.$WEBSITE_NAME/privkey.pem;
      include /etc/letsencrypt/options-ssl-nginx.conf;
      ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

      # Add Headers for odoo proxy mode
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Real-IP \$remote_addr;
      add_header X-Frame-Options "SAMEORIGIN";
      add_header X-XSS-Protection "1; mode=block";
      proxy_set_header X-Client-IP \$remote_addr;
      proxy_set_header HTTP_X_FORWARDED_HOST \$remote_addr;

      # Odoo log files
      access_log /var/log/nginx/$NAME-access.log;
      error_log /var/log/nginx/$NAME-error.log;

      # Increase proxy buffer size
      proxy_buffers 16 64k;
      proxy_buffer_size 128k;

      proxy_read_timeout 900s;
      proxy_connect_timeout 900s;
      proxy_send_timeout 900s;

      # Force timeouts if the backend dies
      proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

      types {
          text/less less;
          text/scss scss;
      }

      # Enable data compression
      gzip on;
      gzip_min_length 1100;
      gzip_buffers 4 32k;
      gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
      gzip_vary on;
      client_header_buffer_size 4k;
      large_client_header_buffers 4 64k;
      client_max_body_size 0;

      location / {
          proxy_pass http://127.0.0.1:$PORT;
          proxy_redirect off;
      }

      location /longpolling {
          proxy_pass http://127.0.0.1:$CHAT;
      }

      location ~* .(js|css|png|jpg|jpeg|gif|ico)$ {
          expires 2d;
          proxy_pass http://127.0.0.1:$PORT;
          add_header Cache-Control "public, no-transform";
      }

      location ~ /[a-zA-Z0-9_-]*/static/ {
          proxy_cache_valid 200 302 60m;
          proxy_cache_valid 404 1m;
          proxy_buffering on;
          expires 864000;
          proxy_pass http://127.0.0.1:$PORT;
      }
  }
EOF

  sudo ln -s /etc/nginx/sites-available/$NAME /etc/nginx/sites-enabled/$NAME
  #sudo rm /etc/nginx/sites-enabled/default
  sudo service nginx reload
  #sudo su root -c "printf 'proxy_mode = True\n' >> /etc/${OE_CONFIG}.conf"
  echo "Done! The Nginx server is up and running. Configuration can be found at /etc/nginx/sites-available/$NAME"
else
  echo "Nginx isn't installed due to choice of the user!"
fi




#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------

if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "adwat.alnjah@gmail.com" ];then
  #sudo add-apt-repository ppa:certbot/certbot -y && sudo apt-get update -y
  #sudo apt-get install python-certbot-nginx -y
  sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  sudo service nginx reload
  echo "SSL/HTTPS is enabled!"
else
  echo "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
fi



echo "URL : $NAME_URL.$WEBSITE_NAME"

echo "------------------------- DNS Record Adding ----------------------------------"

# Load Cloudflare API token from the configuration file
CLOUDFLARE_INI_PATH="$HOME/.secrets/certbot/cloudflare.ini"
if [[ -f $CLOUDFLARE_INI_PATH ]]; then
  API_TOKEN=$(grep 'dns_cloudflare_api_token' $CLOUDFLARE_INI_PATH | cut -d'=' -f2 | tr -d ' ')
  ZONE_ID=$(grep 'zone_id' $CLOUDFLARE_INI_PATH | cut -d'=' -f2 | tr -d ' ')
else
  echo "Cloudflare configuration file not found!"
  exit 1
fi



echo "-------------------------$ip4_address----------------------------------"

# Function to create DNS record in Cloudflare
create_dns_record() {
  # Combine user and website name for subdomain
  subdomain="$NAME_URL.$WEBSITE_NAME"

  RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$subdomain\",\"content\":\"$ip4_address\",\"ttl\":0,\"proxied\":false}")

  if [[ $RESPONSE == *'"success":true'* ]]; then
    echo "Subdomain $subdomain created successfully."
  else
    echo "Failed to create subdomain. Response from Cloudflare:"
    echo $RESPONSE
  fi
}

# Create the DNS record with the combined subdomain
create_dns_record

sleep 10

#--------------------------------------------------
# Install SSL certificate with Certbot
#--------------------------------------------------
echo -e "\n---- Install SSL certificate with Certbot ----"
sudo systemctl restart nginx
sudo certbot certonly --standalone -d $NAME_URL.$WEBSITE_NAME
sudo systemctl restart nginx
systemctl status nginx.service