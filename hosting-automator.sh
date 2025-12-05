#!/bin/bash

# ==============================================================================
#           Hosting Automator: Nginx & Wildcard SSL Setup Script
#                           --- Definitive Version ---
#
# This script can perform two main actions:
# 1. SETUP: A full installation and configuration of the web server.
# 2. UNINSTALL: A complete removal of all changes made by the setup process.
#
# This version creates a professional hosting structure:
# - yourdomain.com -> Redirects to www.yourdomain.com
# - www.yourdomain.com -> Served from /var/www/SERVER/www/
# - *.yourdomain.com -> Served dynamically from /var/www/SERVER/subdomains/
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Colors for better output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color
STEP_COUNT=1

# --- Helper function for printing styled steps ---
print_step() {
  echo -e "\n${BLUE}═══ Step ${STEP_COUNT}: $1 ${NC}"
  ((STEP_COUNT++))
}

# ==============================================================================
#                             SETUP FUNCTION
# ==============================================================================
run_setup() {
  print_step "Initial Configuration"

  echo -n "Checking for required tools (curl, dig)... "
  if ! command -v curl &>/dev/null || ! command -v dig &>/dev/null; then
    echo -e "${YELLOW}Not found. Installing...${NC}"
    apt-get update &>/dev/null
    apt-get install -y curl dnsutils &>/dev/null
  fi
  echo -e "${GREEN}OK.${NC}"

  echo -n "Detecting public IPv4 address... "
  SERVER_IP=$(curl -s https://ipv4.icanhazip.com)
  if [ -z "$SERVER_IP" ]; then SERVER_IP=$(curl -s https://api.ipify.org); fi
  if [ -z "$SERVER_IP" ]; then SERVER_IP=$(dig +short myip.opendns.com @resolver1.opendns.com); fi
  if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}Fatal: Could not determine public IPv4.${NC}"
    exit 1
  fi
  echo -e "${GREEN}Done.${NC}"

  read -p "Please enter your root domain (e.g., seolitic.ai): " DOMAIN
  if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain cannot be empty.${NC}"
    exit 1
  fi

  echo -e "\n${GREEN}✔ Configuration successful.${NC}"
  echo -e "  - Domain: ${YELLOW}$DOMAIN${NC}"
  echo -e "  - Detected Public IPv4: ${YELLOW}$SERVER_IP${NC}"

  echo -e "\n${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗"
  echo -e "║${NC}                           ${YELLOW}ACTION REQUIRED: DNS Setup${NC}                           ${YELLOW}║"
  echo -e "║${NC} Before we proceed, you ${YELLOW}MUST${NC} configure the following DNS records.              ${YELLOW}║"
  echo -e "╠══════════════════════════════════════════════════════════════════════════════╣"
  echo -e "║ ${BLUE}Record 1: Root Domain (A Record)${NC}       - Name: ${YELLOW}@${NC}     Value: ${YELLOW}${SERVER_IP}${NC}        ${YELLOW}║"
  echo -e "║ ${BLUE}Record 2: Wildcard Subdomains (A Record)${NC} - Name: ${YELLOW}*${NC}     Value: ${YELLOW}${SERVER_IP}${NC}        ${YELLOW}║"
  echo -e "╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
  read -p "Press [Enter] to continue once you have set the A records..."

  print_step "Installing Required Packages"
  echo -n "Updating sources and installing Nginx, Certbot, UFW... "
  apt-get update &>/dev/null
  apt-get upgrade -y &>/dev/null
  apt-get install -y nginx certbot python3-certbot-nginx ufw curl dnsutils &>/dev/null
  echo -e "${GREEN}Done.${NC}"

  print_step "Configuring Firewall (UFW)"
  ufw allow 'OpenSSH' &>/dev/null
  ufw allow 'Nginx Full' &>/dev/null
  ufw --force enable &>/dev/null
  echo -e "Status: ${GREEN}Firewall is active and allows SSH, HTTP, and HTTPS traffic.${NC}"

  print_step "Creating Web Directory Structure in /var/www"
  mkdir -p "/var/www/SERVER/www"
  mkdir -p "/var/www/SERVER/subdomains/blog"
  echo "<h1>WWW Main Site Works!</h1>" >"/var/www/SERVER/www/index.html"
  echo "<h1>Blog Subdomain Works!</h1>" >"/var/www/SERVER/subdomains/blog/index.html"
  echo -e "Status: ${GREEN}Web directory structure created.${NC}"

  print_step "Setting Final Directory Permissions"
  chown -R www-data:www-data "/var/www/SERVER"
  find "/var/www/SERVER" -type d -exec chmod 755 {} \;
  find "/var/www/SERVER" -type f -exec chmod 644 {} \;
  echo -e "Status: ${GREEN}Ownership and permissions correctly applied.${NC}"

  print_step "Preparing Nginx for SSL Certificate"
  rm -f /etc/nginx/sites-enabled/default
  cat >/etc/nginx/sites-available/$DOMAIN <<EOF
server { listen 80; listen [::]:80; server_name $DOMAIN *.$DOMAIN; root /var/www/html; }
EOF
  ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
  systemctl reload nginx
  echo -e "Status: ${GREEN}Temporary Nginx configuration applied.${NC}"

  print_step "Obtaining Wildcard SSL Certificate (Interactive)"
  echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗"
  echo -e "║${NC}                       ${YELLOW}ACTION REQUIRED: Certbot DNS Challenge${NC}                     ${YELLOW}║"
  echo -e "║${NC} The script will now run Certbot. It will pause and show you a TXT record.      ${YELLOW}║"
  echo -e "║${RED} IMPORTANT:${NC} Certbot may ask you to create a ${YELLOW}SECOND${NC} TXT record.            ${YELLOW}║"
  echo -e "║ If it does, you must ${YELLOW}ADD${NC} the second record. ${RED}DO NOT${NC} replace the first one.   ${YELLOW}║"
  echo -e "╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
  read -p "Press [Enter] to begin the interactive Certbot process..."
  certbot certonly --manual --preferred-challenges=dns -d "$DOMAIN" -d "*.$DOMAIN"
  if [ ! -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
    echo -e "${RED}Fatal: Certbot failed. Certificate not created. Exiting.${NC}"
    exit 1
  fi
  echo -e "${GREEN}✔ SSL Certificate successfully obtained!${NC}"

  print_step "Applying Final Nginx Configuration"
  echo -n "Creating SSL parameters and Nginx config... "
  mkdir -p /etc/letsencrypt/
  cat >/etc/letsencrypt/options-ssl-nginx.conf <<EOF
ssl_session_cache shared:le_nginx_SSL:10m; ssl_session_timeout 1440m; ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3; ssl_prefer_server_ciphers off;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
EOF
  openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048 &>/dev/null
  cat >/etc/nginx/sites-available/$DOMAIN <<EOF
server { # Redirects the APEX/ROOT domain to WWW
    listen 443 ssl http2; listen [::]:443 ssl http2; server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf; ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    return 301 https://www.$DOMAIN\$request_uri;
}
server { # Handles the WWW subdomain specifically
    listen 443 ssl http2; listen [::]:443 ssl http2; server_name www.$DOMAIN;
    root /var/www/SERVER/www; index index.html;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf; ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
server { # Dynamically handles ALL OTHER subdomains
    listen 443 ssl http2; listen [::]:443 ssl http2;
    server_name ~^(?!www\.)(?<subdomain>.+)\.$DOMAIN$;
    root /var/www/SERVER/subdomains/\$subdomain; index index.html;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf; ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
server { # Redirects all HTTP traffic to HTTPS
    listen 80; listen [::]:80; server_name $DOMAIN *.$DOMAIN;
    location / { return 301 https://\$host\$request_uri; }
}
EOF
  nginx -t &>/dev/null
  systemctl reload nginx
  echo -e "${GREEN}Done.${NC}"

  print_step "Creating Renewal Information File"
  CREATED_DATE=$(date +%d.%m.%Y)
  EXPIRY_STRING=$(openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN/cert.pem | cut -d'=' -f2)
  EXPIRY_DATE=$(date -d "$EXPIRY_STRING" +%d.%m.%Y)
  cat >"$HOME/certbot-renewal-information.txt" <<EOF
# SSL Certificate Renewal Information for $DOMAIN
Certificate Created On:         $CREATED_DATE
Certificate Expires On:         $EXPIRY_DATE
You must MANUALLY renew before the expiry date. To renew, run: certbot renew
After renewing, reload Nginx: systemctl reload nginx
EOF
  echo -e "Status: ${GREEN}Renewal info saved to $HOME/certbot-renewal-information.txt${NC}"

  echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗"
  echo -e "║                             ${GREEN}SETUP COMPLETE!${NC}                               ║"
  echo -e "╠══════════════════════════════════════════════════════════════════════════════╣"
  echo -e "║ ${BLUE}$DOMAIN${NC} permanently redirects to ${YELLOW}www.$DOMAIN${NC}                          ║"
  echo -e "║ ${BLUE}www.$DOMAIN${NC} is served from ${YELLOW}/var/www/SERVER/www/${NC}                        ║"
  echo -e "║ ${BLUE}any.sub.${DOMAIN}${NC} is served from ${YELLOW}/var/www/SERVER/subdomains/any/${NC}         ║"
  echo -e "║                                                                              ║"
  echo -e "║ To add a new subdomain (e.g., portfolio):                                    ║"
  echo -e "║   ${YELLOW}mkdir /var/www/SERVER/subdomains/portfolio${NC}                                 ║"
  echo -e "║   ${YELLOW}chown -R www-data:www-data /var/www/SERVER/subdomains/portfolio${NC}              ║"
  echo -e "║                                                                              ║"
  echo -e "║ ${RED}IMPORTANT:${NC} Remember to manually renew your SSL certificate!                 ║"
  echo -e "╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# ==============================================================================
#                             UNINSTALL FUNCTION
# ==============================================================================
run_uninstall() {
  echo -e "\n${RED}--- UNINSTALL / ROLLBACK ---${NC}"
  read -p "Please enter the root domain used during setup (e.g., seolitic.ai): " DOMAIN
  if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain cannot be empty.${NC}"
    exit 1
  fi
  read -p "Are you sure you want to remove all files and packages for $DOMAIN? [y/N]: " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Uninstall cancelled."
    exit 0
  fi

  echo -n "Stopping services and removing packages... "
  systemctl stop nginx || true
  systemctl disable nginx || true
  apt-get purge --auto-remove -y nginx nginx-common certbot python3-certbot-nginx curl dnsutils &>/dev/null
  echo -e "${GREEN}Done.${NC}"

  echo -n "Deleting Let's Encrypt certificates... "
  rm -rf /etc/letsencrypt/
  echo -e "${GREEN}Done.${NC}"

  echo -n "Resetting Firewall (UFW)... "
  ufw delete allow 'Nginx Full' || true
  echo -e "${GREEN}Done.${NC}"

  echo -n "Removing files and directories... "
  rm -f /etc/nginx/sites-enabled/$DOMAIN
  rm -f /etc/nginx/sites-available/$DOMAIN
  rm -rf "/var/www/SERVER"
  rm -f "$HOME/certbot-renewal-information.txt"
  echo -e "${GREEN}Done.${NC}"

  echo -e "\n${GREEN}✔ Uninstall Complete. All changes have been rolled back.${NC}"
}

# ==============================================================================
#                                SCRIPT MAIN LOGIC
# ==============================================================================
clear
# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root. Please use 'sudo ./hosting-automator.sh' or run as the root user.${NC}"
  exit 1
fi

echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      ${NC}Hosting Automator: Nginx & Wildcard SSL      ${BLUE}║${NC}"
echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
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
