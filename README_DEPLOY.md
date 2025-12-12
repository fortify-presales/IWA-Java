Deploying IWA to an AWS Ubuntu server (no Docker)

Overview
--------
This document explains how to deploy the IWA Spring Boot application using GitHub Actions to an Ubuntu server (AWS EC2). The approach uses a runnable jar, a systemd service, nginx as a reverse proxy, and certbot for TLS.

Files added to this repo
- .github/workflows/deploy.yml            - GitHub Actions workflow (build + scp + remote deploy)
- deploy/remote_deploy.sh                 - Idempotent remote deployment script
- deploy/templates/ (systemd/nginx/env)   - templates for server-side configuration
- README_DEPLOY.md                        - this file

Pre-requisites on server
- Ubuntu 18.04/20.04/22.04
- OpenJDK 11 (matches project sourceCompatibility)
- nginx
- certbot (snap)
- deploy user (non-root) with sudo privileges for systemctl and file ops

Initial server setup commands (run as sudo/root)

Create deploy user and directories:

```bash
sudo adduser --system --group --home /home/deploy --shell /bin/bash deploy
sudo mkdir -p /opt/iwa/releases /opt/iwa/shared /opt/iwa/logs
sudo chown -R deploy:deploy /opt/iwa
```

Install packages:

```bash
sudo apt update; sudo apt install -y openjdk-11-jre-headless nginx snapd ufw
sudo snap install --classic certbot; sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo ufw allow OpenSSH; sudo ufw allow 'Nginx Full'; sudo ufw enable
```

Place systemd unit and env file (example):

```bash
# copy template to server
sudo cp deploy/templates/iwa.service /etc/systemd/system/iwa.service
sudo cp deploy/templates/etc-default-iwa.sample /etc/default/iwa
# edit /etc/default/iwa with real secrets and JAVA_OPTS; then:
sudo systemctl daemon-reload
sudo systemctl enable iwa.service
sudo systemctl start iwa.service
sudo systemctl status iwa.service
```

Obtain TLS cert via certbot after configuring nginx:

```bash
sudo cp deploy/templates/nginx-iwa.conf /etc/nginx/sites-available/iwa
sudo ln -s /etc/nginx/sites-available/iwa /etc/nginx/sites-enabled/
sudo nginx -t; sudo systemctl reload nginx
# replace example.com with your domain iwa.onfortify.com
sudo certbot --nginx -d iwa.onfortify.com
```

GitHub Actions setup
- Add the following secrets in your repository settings:
  - SSH_PRIVATE_KEY (the PEM private key of deploy key) - add the contents of your private key file `C:\Users\klee2\OpenText Core\Keys\KevinLeeMF.pem` as the secret value
  - SSH_KNOWN_HOSTS (output from ssh-keyscan -t rsa iwa.onfortify.com)
  - EC2_USER (e.g., deploy)
  - EC2_HOST (server IP or DNS name iwa.onfortify.com)
  - SSH_PORT (optional, default 22)

Usage
- Push to `main` branch to trigger the workflow which builds and deploys the jar to the server.

Rollback
- The `remote_deploy.sh` automatically attempts to rollback to the previous release if the health check fails. To manually rollback:

```bash
sudo ls -1dt /opt/iwa/releases/*
sudo ln -sfn /opt/iwa/releases/<previous> /opt/iwa/current
sudo systemctl restart iwa.service
```

- Copy files to server (PowerShell):
```powershell
$KEY = "C:\Users\klee2\OpenText Core\Keys\KevinLeeMF.pem"
-$HOST = "iwa.onfortify.com"
-$USER = "deploy"
-scp -i "$KEY" -P 22 build\libs\*.jar $USER@$HOST:/tmp/iwa.jar
-scp -i "$KEY" -P 22 deploy\remote_deploy.sh $USER@$HOST:/tmp/remote_deploy.sh
+$EC2_HOST = "iwa.onfortify.com"
+$EC2_USER = "deploy"
+scp -i "$KEY" -P 22 build\libs\*.jar $EC2_USER@$EC2_HOST:/tmp/iwa.jar
+scp -i "$KEY" -P 22 deploy\remote_deploy.sh $EC2_USER@$EC2_HOST:/tmp/remote_deploy.sh
```
- Install templates and run deploy (on server):
```bash
# move templates to the correct system paths (one-time):
sudo mv /tmp/iwa.service /etc/systemd/system/iwa.service
sudo mv /tmp/etc-default-iwa.sample /etc/default/iwa
sudo mv /tmp/nginx-iwa.conf /etc/nginx/sites-available/iwa
sudo ln -sfn /etc/nginx/sites-available/iwa /etc/nginx/sites-enabled/iwa
sudo chown root:root /etc/systemd/system/iwa.service /etc/default/iwa /etc/nginx/sites-available/iwa
sudo chmod 644 /etc/systemd/system/iwa.service /etc/nginx/sites-available/iwa
sudo chmod 640 /etc/default/iwa

# make deploy script executable
sudo mv /tmp/remote_deploy.sh /home/deploy/remote_deploy.sh
sudo chown deploy:deploy /home/deploy/remote_deploy.sh
sudo chmod 755 /home/deploy/remote_deploy.sh

# run deploy (this will create a release, swap current and restart service):
bash /home/deploy/remote_deploy.sh /tmp/iwa.jar
```
