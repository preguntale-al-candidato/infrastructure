#!/bin/bash

# Install docker
sudo yum install docker -y
sudo service docker start
sudo chkconfig docker on
docker version

# Install docker-compose
sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose version

# API_KEY=$(aws ssm get-parameter --name "your_parameter_name" --with-decryption --query "Parameter.Value" --output text)
# docker run -e API_KEY=$API_KEY your_docker_image_name
