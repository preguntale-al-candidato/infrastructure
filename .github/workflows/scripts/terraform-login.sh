#!/usr/bin/env bash

mkdir -p ~/.terraform.d

cat > ~/.terraform.d/credentials.tfrc.json << EOL
{
  "credentials": {
    "app.terraform.io": {
      "token": "${{ secrets.TF_CLOUD_TOKEN }}"
    }
  }
}
EOL
