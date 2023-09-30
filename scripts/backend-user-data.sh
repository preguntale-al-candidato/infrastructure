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
docker version

# Install docker-compose
sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose version

# Run Milvus DB
wget https://github.com/milvus-io/milvus/releases/download/v2.3.1/milvus-standalone-docker-compose.yml -O docker-compose.yml
sudo docker-compose up -d

# API_KEY=$(aws ssm get-parameter --name "your_parameter_name" --with-decryption --query "Parameter.Value" --output text)
API_KEY=$(echo hola1234)

# Run backend
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 301634789447.dkr.ecr.us-east-1.amazonaws.com
docker pull 301634789447.dkr.ecr.us-east-1.amazonaws.com/pac-backend:latest


# docker run --rm -d -p 8000:80 --name sample nginx
docker run --rm -d -p 8000:8000 --name backend -e API_KEY=$API_KEY 301634789447.dkr.ecr.us-east-1.amazonaws.com/pac-backend:latest
