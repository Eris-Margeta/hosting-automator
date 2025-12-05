#!/bin/bash

# ==============================================================================
#           Hosting Automator: Nginx & Wildcard SSL Setup Script
#
# This script can perform two main actions:
# 1. SETUP: A full installation and configuration of the web server.
# 2. UNINSTALL: A complete removal of all changes made by the setup process.
#
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Colors for better output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ==============================================================================
#                             SETUP FUNCTION
# ==============================================================================
run_setup() {
  # --- User Input ---
  echo -e "${BLUE}--- Server & Domain Configuration ---${NC}"
  read -p "Please enter your root domain (e.g., tejl.com): " DOMAIN
  read -p "Please enter your server's public IP address (e.g., 93.136.180.191): " SERVER_IP

  if [ -z "$DOMAIN" ] || [ -z "$SERVER_IP" ]; then
    echo -e "${RED}Error: Domain and Server IP cannot be empty. Exiting.${NC}"
    exit 1
  fi

  echo -e "\n${GREEN}Configuration successful. Domain: ${DOMAIN}, IP: ${SERVER_IP}${NC}"

  # --- DNS Setup Instructions ---
  echo -e "\n${YELLOW}========================= ACTION REQUIRED: DNS Setup =========================${NC}"
  echo -e "Before we proceed, you ${YELLOW}MUST${NC} configure the following DNS records in your domain provider's control panel."
  echo -e ""
  echo -e "1. ${BLUE}Root Domain A Record:${NC}   (Type: A, Name: @, Value: ${SERVER_IP})"
  echo -e "2. ${BLUE}Wildcard Domain A Record:${NC} (Type: A, Name: *, Value: ${SERVER_IP})"
  echo -e ""
  echo -e "${YELLOW}Please set up these two A records now.${NC}"
  read -p "Press [Enter] to continue once you have set the A records..."

  # --- Step 1: System Update & Package Installation ---
  echo -e "\n${BLUE}--- Updating system and installing required packages... ---${NC}"
  apt update
  apt upgrade -y
  apt install -y nginx certbot python3-certbot-nginx ufw

  # --- Step 2: Firewall Configuration ---
  echo -e "\n${BLUE}--- Configuring Firewall (UFW)... ---${NC}"
  ufw allow 'OpenSSH'
  ufw allow 'Nginx Full'
  ufw --force enable
  echo -e "${GREEN}Firewall is active and allows SSH, HTTP, and HTTPS traffic.${NC}"

  # --- Step 3: Directory and Initial Nginx Setup ---
  echo -e "\n${BLUE}--- Creating web directory and setting up Nginx... ---${NC}"
  mkdir -p /root/www/root
  echo "<h1>Main Domain Page - Hosted from /root/www/root</h1>" >/root/www/root/index.html
  chown -R www-data:www-data /root/www
  echo -e "Created web directory at /root/www"
  rm -f /etc/nginx/sites-enabled/default

  cat >/etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN *.$DOMAIN;
    root /var/www/html; # Temporary default root
    index index.html;
}
EOF

  ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
  nginx -t
  systemctl reload nginx
  echo -e "${GREEN}Nginx has been installed and configured with a temporary site for ${DOMAIN}.${NC}"

  # --- Step 4: Wildcard SSL Certificate with Certbot ---
  echo -e "\n${YELLOW}==================== ACTION REQUIRED: Certbot DNS Challenge ====================${NC}"
  echo -e "The script will now run Certbot to get your wildcard SSL certificate."
  echo -e "${RED}IMPORTANT:${NC} Certbot may ask you to create a SECOND TXT record."
  echo -e "If it does, you must ${YELLOW}ADD${NC} the second record. ${RED}DO NOT${NC} replace the first one."
  echo -e "You will need to have ${YELLOW}TWO SEPARATE TXT records${NC} with the same name in your DNS provider."
  read -p "Press [Enter] to begin the interactive Certbot process..."

  certbot certonly --manual --preferred-challenges=dns -d "$DOMAIN" -d "*.$DOMAIN"

  if [ ! -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
    echo -e "${RED}Certbot failed. Certificate not created. Exiting.${NC}"
    exit 1
  fi
  echo -e "${GREEN}SSL Certificate successfully obtained!${NC}"

  # --- Step 5: Final Nginx Configuration ---
  echo -e "\n${BLUE}--- Applying final Nginx configuration... ---${NC}"

  # FIX: Create the missing Let's Encrypt options file to prevent Nginx error.
  mkdir -p /etc/letsencrypt/
  cat >/etc/letsencrypt/options-ssl-nginx.conf <<EOF
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;

ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
EOF
  # FIX: Generate a Diffie-Hellman group file used by the options file above.
  openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048

  # Now, write the final Nginx config
  cat >/etc/nginx/sites-available/$DOMAIN <<EOF
# This server block handles the root domain (e.g., tejl.com)
server {
    # FIX: Updated listen directive to modern syntax to avoid warnings.
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name $DOMAIN;
    root /root/www/root;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

# This server block dynamically handles all subdomains (e.g., blog.tejl.com)
server {
    # FIX: Updated listen directive to modern syntax to avoid warnings.
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    server_name ~^(?<subdomain>.+)\.$DOMAIN$;
    root /root/www/\$subdomain;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

# Redirect all HTTP traffic to HTTPS for security
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN *.$DOMAIN;
    location / { return 301 https://\$host\$request_uri; }
}
EOF
  nginx -t
  systemctl reload nginx
  echo -e "${GREEN}Final Nginx configuration has been applied.${NC}"

  # --- Step 6: Create Renewal Information File ---
  echo -e "\n${BLUE}--- Creating renewal information file... ---${NC}"
  cat >/root/certbot-renewal-information.txt <<EOF
# SSL Certificate Renewal Information for $DOMAIN
Your wildcard SSL certificate was generated using Certbot's "manual" method.
This means it CANNOT be renewed automatically.
You must MANUALLY renew the certificate before it expires (every 90 days).
To renew, run the following command and follow the on-screen instructions:
  certbot renew
To check the expiry date of your current certificate, run:
  openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN/cert.pem
EOF
  echo -e "${GREEN}Renewal information saved to /root/certbot-renewal-information.txt${NC}"

  # --- Final Summary ---
  echo -e "\n${GREEN}============================= SETUP COMPLETE! ==============================${NC}"
  echo -e "To add a new site (e.g., https://blog.${DOMAIN}), run:"
  echo -e "  ${YELLOW}mkdir /root/www/blog${NC}"
  echo -e "  ${YELLOW}echo '<h1>Hello Blog!</h1>' > /root/www/blog/index.html${NC}"
  echo -e "  ${YELLOW}chown -R www-data:www-data /root/www/blog${NC}"
  echo -e "${YELLOW}IMPORTANT: Remember to manually renew your SSL certificate!${NC}"
  echo -e "${GREEN}==========================================================================${NC}"
}

# ==============================================================================
#                             UNINSTALL FUNCTION
# ==============================================================================
run_uninstall() {
  echo -e "\n${RED}--- UNINSTALL / ROLLBACK ---${NC}"
  read -p "Please enter the root domain you used during setup (e.g., tejl.com): " DOMAIN
  if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain cannot be empty. Exiting.${NC}"
    exit 1
  fi

  read -p "Are you sure you want to remove all Nginx, Certbot, and related files for $DOMAIN? [y/N]: " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "Uninstall cancelled."
    exit 0
  fi

  echo -e "\n${BLUE}--- Stopping and disabling services... ---${NC}"
  systemctl stop nginx || true
  systemctl disable nginx || true

  echo -e "\n${BLUE}--- Removing packages... ---${NC}"
  apt purge --auto-remove -y nginx nginx-common certbot python3-certbot-nginx || true

  echo -e "\n${BLUE}--- Deleting Let's Encrypt certificates and files... ---${NC}"
  # Remove the entire letsencrypt directory which contains certs, configs, and our helper files
  rm -rf /etc/letsencrypt/

  echo -e "\n${BLUE}--- Resetting Firewall (UFW)... ---${NC}"
  ufw delete allow 'Nginx Full' || true
  echo -e "Firewall rule for Nginx removed."

  echo -e "\n${BLUE}--- Removing files and directories... ---${NC}"
  rm -f /etc/nginx/sites-enabled/$DOMAIN
  rm -f /etc/nginx/sites-available/$DOMAIN
  rm -rf /root/www
  rm -f /root/certbot-renewal-information.txt

  echo -e "\n${GREEN}========================= UNINSTALL COMPLETE =========================${NC}"
  echo -e "All associated packages, configurations, and files have been removed."
  echo -e "${GREEN}======================================================================${NC}"
}

# ==============================================================================
#                                SCRIPT MAIN LOGIC
# ==============================================================================
clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}      Hosting Automator: Nginx & Wildcard SSL       ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e ""
echo -e "Please choose an action to perform:"
echo -e "  1) ${GREEN}SETUP${NC}:    Run the full installation and configuration."
echo -e "  2) ${RED}UNINSTALL${NC}: Roll back all changes made by this script."
echo -e ""
read -p "Enter your choice (1 or 2): " ACTION

case $ACTION in
1)
  run_setup
  ;;
2)
  run_uninstall
  ;;
*)
  echo -e "${RED}Invalid choice. Please run the script again and enter 1 or 2.${NC}"
  exit 1
  ;;
esac
