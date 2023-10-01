#!/bin/bash

# Update packages
sudo dnf --assumeyes update

# Install docker
sudo dnf --assumeyes install wget docker
sudo systemctl start docker
sudo systemctl enable docker
sudo systemctl status docker
sudo usermod -aG docker $USER
newgrp docker
sudo docker version

# Install docker-compose
sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose version

# Set environment variables
cat > /tmp/backend.env <<EOL
API_KEY=$(echo hola1234)
EOL
# OPENAI_API_KEY=$(aws ssm get-parameter --name "your_parameter_name" --with-decryption --query "Parameter.Value" --output text)

# ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 301634789447.dkr.ecr.us-east-1.amazonaws.com

cat > /tmp/docker-compose.yml <<EOL
version: "3.8"

services:
  etcd:
    container_name: milvus-etcd
    image: quay.io/coreos/etcd:v3.5.5
    environment:
      - ETCD_AUTO_COMPACTION_MODE=revision
      - ETCD_AUTO_COMPACTION_RETENTION=1000
      - ETCD_QUOTA_BACKEND_BYTES=4294967296
      - ETCD_SNAPSHOT_COUNT=50000
    volumes:
      - ${DOCKER_VOLUME_DIRECTORY:-.}/volumes/etcd:/etcd
    command: etcd -advertise-client-urls=http://127.0.0.1:2379 -listen-client-urls http://0.0.0.0:2379 --data-dir /etcd
    healthcheck:
      test: ["CMD", "etcdctl", "endpoint", "health"]
      interval: 30s
      timeout: 20s
      retries: 3

  minio:
    container_name: milvus-minio
    image: minio/minio:RELEASE.2023-03-20T20-16-18Z
    environment:
      MINIO_ACCESS_KEY: minioadmin
      MINIO_SECRET_KEY: minioadmin
    ports:
      - "9001:9001"
      - "9000:9000"
    volumes:
      - ${DOCKER_VOLUME_DIRECTORY:-.}/volumes/minio:/minio_data
    command: minio server /minio_data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  standalone:
    container_name: milvus-standalone
    image: milvusdb/milvus:v2.3.1
    command: ["milvus", "run", "standalone"]
    environment:
      ETCD_ENDPOINTS: etcd:2379
      MINIO_ADDRESS: minio:9000
    volumes:
      - ${DOCKER_VOLUME_DIRECTORY:-.}/volumes/milvus:/var/lib/milvus
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9091/healthz"]
      interval: 30s
      start_period: 90s
      timeout: 20s
      retries: 3
    ports:
      - "19530:19530"
      - "9091:9091"
    depends_on:
      etcd:
        condition: service_healthy
      minio:
        condition: service_healthy

  backend:
    container_name: backend
    image: 301634789447.dkr.ecr.us-east-1.amazonaws.com/pac-backend:latest
    environment:
      OPENAI_API_KEY: "\${API_KEY}"
      MILVUS_HOST: standalone
      MILVUS_PORT: 19530
    ports:
      - "8000:8000"
    depends_on:
      standalone:
        condition: service_healthy

networks:
  default:
    name: pac
EOL

sudo docker-compose --project-name pac --env-file /tmp/backend.env --file /tmp/docker-compose.yml up --detach
