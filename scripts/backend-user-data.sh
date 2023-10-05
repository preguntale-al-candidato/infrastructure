#!/bin/bash

# Set work dir
WORK_DIR=/app
mkdir -p $WORK_DIR

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
cat > $WORK_DIR/backend.env <<EOL
OPENAI_API_KEY=$(aws ssm get-parameter --name "OPEN_AI_API_KEY" --with-decryption --query "Parameter.Value" --output text)
MILVUS_HOST=172.16.10.52
MILVUS_PORT=19530
EOL

# ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 301634789447.dkr.ecr.us-east-1.amazonaws.com

# Run backend
sudo docker run -d --name backend --env-file $WORK_DIR/backend.env -p 8000:8000 --restart=unless-stopped 301634789447.dkr.ecr.us-east-1.amazonaws.com/pac-backend:latest
