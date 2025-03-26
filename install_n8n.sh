#!/bin/bash

# Kiểm tra xem script có được chạy với quyền root không
if [[ $EUID -ne 0 ]]; then
   echo "This script needs to be run with root privileges" 
   exit 1
fi

# Hàm kiểm tra domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain đã trỏ đúng
    else
        return 1  # Domain chưa trỏ đúng
    fi
}

# Nhận input domain từ người dùng
read -p "Enter your domain or subdomain: " DOMAIN

# Kiểm tra domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN has been correctly pointed to this server. Continuing installation"
else
    echo "Domain $DOMAIN has not been pointed to this server."
    echo "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again"
    exit 1
fi

# Sử dụng thư mục /home trực tiếp
N8N_DIR="/home/n8n"

# Cài đặt Docker và Docker Compose
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Tạo thư mục cho n8n
mkdir -p $N8N_DIR

# Tạo file docker-compose.yml
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3"
services:
  n8n:
    container_name: n8n
    image: n8nio/n8n:latest
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - N8N_BINARY_DATA_STORAGE=/home/node/.n8n/binaryData
      - N8N_DEFAULT_BINARY_DATA_FILESYSTEM_DIRECTORY=/home/node/.n8n/binaryData
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_REDIS_HOST=redis
      - N8N_REDIS_PORT=6379
      - N8N_REDIS_PASSWORD=yourpassword
      - N8N_SECURE_COOKIE=false
      # Cấu hình kết nối PostgreSQL
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=n8npassword
    user: "root"
    volumes:
      - /home/n8n:/home/node/.n8n
      - /home/n8n/binaryData:/home/node/.n8n/binaryData
      - /home/node:/home/node
      - /home/n8n:/root/.n8n
    depends_on:
      - redis
      - postgres
    networks:
      - n8n_network

  postgres:
    container_name: postgres
    image: postgres:16
    restart: always
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=n8npassword
      - POSTGRES_DB=n8n
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n_network

  redis:
    container_name: redis
    image: redis:latest
    restart: always
    command: redis-server --requirepass "yourpassword"
    ports:
      - "6379:6379"
    networks:
      - n8n_network

  caddy:
    image: caddy:2
    restart: always
    ports:
      - "8080:80"
      - "8443:443"
    volumes:
      - /home/n8n/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
      - /home/node:/srv/data
    depends_on:
      - n8n
    networks:
      - n8n_network

networks:
  n8n_network:

volumes:
  caddy_data:
  caddy_config:
  postgres_data:
EOF

# Tạo file Caddyfile
cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678 {
        header_up X-Forwarded-Proto {scheme}
    }
}

video.${DOMAIN} {
    root * /srv/data
    file_server browse
}
EOF

# Đặt quyền cho thư mục n8n
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Khởi động các container
cd $N8N_DIR
docker-compose up -d

echo "N8n đã được cài đặt và cấu hình với SSL sử dụng Caddy. Truy cập https://${DOMAIN} để sử dụng."
echo "Các file cấu hình và dữ liệu được lưu trong $N8N_DIR"
echo "Script tạo bởi Dunn"
