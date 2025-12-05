#!/bin/bash

# ==============================================================================
#           Hosting Automator: Nginx & Wildcard SSL Setup Script
#
# This script is intended to be run on a fresh Debian server as the root user.
#
# It will:
# 1. Ask for your domain and server IP address.
# 2. Provide instructions for setting up the required DNS A records.
# 3. Install and configure UFW, Nginx, and Certbot.
# 4. Guide you through the interactive Certbot DNS challenge for a wildcard cert.
# 5. Configure Nginx to serve static sites from subdirectories dynamically.
# 6. Create a detailed information file for the manual SSL renewal process.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Colors for better output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- User Input ---
echo -e "${BLUE}--- Server & Domain Configuration ---${NC}"
read -p "Please enter your root domain (e.g., tejl.com): " DOMAIN
read -p "Please enter your server's public IP address (e.g., 93.136.180.191): " SERVER_IP

if [ -z "$DOMAIN" ] || [ -z "$SERVER_IP" ]; then
  echo -e "${YELLOW}Error: Domain and Server IP cannot be empty. Exiting.${NC}"
  exit 1
fi

echo -e "\n${GREEN}Configuration successful. Domain: ${DOMAIN}, IP: ${SERVER_IP}${NC}"

# --- DNS Setup Instructions ---
echo -e "\n${YELLOW}========================= ACTION REQUIRED: DNS Setup =========================${NC}"
echo -e "Before we proceed, you ${YELLOW}MUST${NC} configure the following DNS records in your domain provider's control panel."
echo -e "The script will wait for you to do this."
echo ""
echo -e "1. ${BLUE}Root Domain A Record:${NC}"
echo -e "   - Type:    A"
echo -e "   - Name:    @"
echo -e "   - Value:   ${SERVER_IP}"
echo ""
echo -e "2. ${BLUE}Wildcard Domain A Record:${NC}"
echo -e "   - Type:    A"
echo -e "   - Name:    *"
echo -e "   - Value:   ${SERVER_IP}"
echo ""
echo -e "DNS changes can take a few minutes to propagate."
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
# Use --force to enable without interactive prompts, which is good for scripts.
ufw --force enable
echo -e "${GREEN}Firewall is active and allows SSH, HTTP, and HTTPS traffic.${NC}"

# --- Step 3: Directory and Initial Nginx Setup ---
echo -e "\n${BLUE}--- Creating web directory and setting up Nginx... ---${NC}"
# Create the www directory in the root user's home
mkdir -p /root/www
# Create a specific directory for the root domain itself
mkdir -p /root/www/root
echo "<h1>Main Domain Page - Hosted from /root/www/root</h1>" >/root/www/root/index.html
# Set ownership to the web server user
chown -R www-data:www-data /root/www
echo -e "Created web directory at /root/www"

# Remove the default Nginx configuration to avoid conflicts
rm -f /etc/nginx/sites-enabled/default

# Create a temporary Nginx configuration for Certbot validation
cat >/etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN *.$DOMAIN;
    root /var/www/html; # Temporary default root
    index index.html;
}
EOF

# Enable the new configuration by creating a symlink
ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# Test Nginx config and reload the service
nginx -t
systemctl reload nginx
echo -e "${GREEN}Nginx has been installed and configured with a temporary site for ${DOMAIN}.${NC}"

# --- Step 4: Wildcard SSL Certificate with Certbot ---
echo -e "\n${YELLOW}==================== ACTION REQUIRED: Certbot DNS Challenge ====================${NC}"
echo -e "The script will now run Certbot to get your wildcard SSL certificate."
echo -e "Certbot will ask for your email and for you to agree to the ToS."
echo -e "Most importantly, it will then pause and show you a ${BLUE}TXT record${NC} to add to your DNS."
echo -e "1. Wait for Certbot to display the TXT record name and value."
echo -e "2. Go to your DNS provider and add this ${BLUE}TXT record${NC}."
echo -e "3. Wait for about ${YELLOW}2-5 minutes${NC} for the DNS record to propagate."
echo -e "4. Return to this terminal and press [Enter] to let Certbot verify the record."
read -p "Press [Enter] to begin the interactive Certbot process..."

certbot certonly --manual --preferred-challenges=dns -d "$DOMAIN" -d "*.$DOMAIN"

# Verify that the certificate was successfully created before proceeding
if [ ! -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
  echo -e "${YELLOW}Certbot failed. The certificate was not created. Please review any error messages and try again. Exiting.${NC}"
  exit 1
fi

echo -e "${GREEN}SSL Certificate successfully obtained!${NC}"

# --- Step 5: Final Nginx Configuration for SSL and Dynamic Subdomains ---
echo -e "\n${BLUE}--- Applying final Nginx configuration for SSL and dynamic subdomains... ---${NC}"

# Overwrite the temporary configuration file with the final, dynamic one
cat >/etc/nginx/sites-available/$DOMAIN <<EOF
# This server block handles the root domain (e.g., tejl.com)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
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
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    # Regex to capture the subdomain part of the hostname
    server_name ~^(?<subdomain>.+)\.$DOMAIN$;

    # Use the captured subdomain to set the document root
    root /root/www/\$subdomain;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

# Redirect all HTTP traffic to HTTPS for security
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN *.$DOMAIN;

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

# Test and reload Nginx with the final SSL configuration
nginx -t
systemctl reload nginx
echo -e "${GREEN}Final Nginx configuration has been applied.${NC}"

# --- Step 6: Create Renewal Information File ---
echo -e "\n${BLUE}--- Creating renewal information file... ---${NC}"

cat >/root/certbot-renewal-information.txt <<EOF
# =========================================================
# SSL Certificate Renewal Information for $DOMAIN
# =========================================================

Your wildcard SSL certificate was generated using Certbot's "manual" method.
This means the standard 'certbot renew' cron job CANNOT automate the renewal.

You must MANUALLY renew the certificate before it expires (certificates are valid for 90 days).

To renew, run the following command. It will prompt you to create a new DNS TXT record, just like you did during the initial setup.

  certbot renew

It is recommended to do this about a week before the certificate expires.
You can check the expiry date of your current certificate with this command:

  openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN/cert.pem
EOF

echo -e "${GREEN}Renewal information saved to /root/certbot-renewal-information.txt${NC}"

# --- Final Summary ---
echo -e "\n${GREEN}============================= SETUP COMPLETE! ==============================${NC}"
echo -e "Your server is now configured to serve dynamic subdomains."
echo -e "To add a new site, simply create a new folder inside the ${BLUE}/root/www/${NC} directory."
echo -e "For example, to create a site at https://blog.${DOMAIN}:"
echo ""
echo -e "  ${YELLOW}mkdir /root/www/blog${NC}"
echo -e "  ${YELLOW}echo '<h1>Hello from the blog!</h1>' > /root/www/blog/index.html${NC}"
echo -e "  ${YELLOW}chown -R www-data:www-data /root/www/blog${NC}"
echo ""
echo -e "Then navigate to https://blog.${DOMAIN} in your browser."
echo ""
echo -e "${YELLOW}IMPORTANT: Remember to manually renew your SSL certificate. See the instructions in /root/certbot-renewal-information.txt${NC}"
echo -e "${GREEN}==========================================================================${NC}"
