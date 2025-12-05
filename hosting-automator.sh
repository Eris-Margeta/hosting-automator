#!/bin/bash

# ==============================================================================
# Nginx & Wildcard SSL Automation Script
#
# This script will:
# 1. Ask for your domain and server IP address.
# 2. Set up required DNS records instructions.
# 3. Install and configure UFW, Nginx, and Certbot.
# 4. Guide you through the interactive Certbot DNS challenge.
# 5. Configure Nginx for dynamic, subdomain-based static sites.
# 6. Create an information file for the manual SSL renewal process.
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
read -p "Please enter your root domain (e.g., TEJL.com): " DOMAIN
read -p "Please enter your server's public IP address (e.g., 93.136.180.191): " SERVER_IP

if [ -z "$DOMAIN" ] || [ -z "$SERVER_IP" ]; then
  echo -e "${YELLOW}Domain and Server IP cannot be empty. Exiting.${NC}"
  exit 1
fi

echo -e "\n${GREEN}Configuration successful. Domain: ${DOMAIN}, IP: ${SERVER_IP}${NC}"

# --- DNS Setup Instructions ---
echo -e "\n${YELLOW}========================= ACTION REQUIRED: DNS Setup =========================${NC}"
echo -e "Before we proceed, you ${YELLOW}MUST${NC} configure the following DNS records in your domain provider's control panel (e.g., Hetzner)."
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
echo -e "\n${BLUE}--- Updating system and installing packages (Nginx, Certbot)... ---${NC}"
apt update
apt upgrade -y
apt install -y nginx certbot python3-certbot-nginx ufw

# --- Step 2: Firewall Configuration ---
echo -e "\n${BLUE}--- Configuring Firewall (UFW)... ---${NC}"
ufw allow 'OpenSSH'
ufw allow 'Nginx Full'
# Use --force to enable without interactive prompts
ufw --force enable
echo -e "${GREEN}Firewall is now active and allows SSH, HTTP, and HTTPS traffic.${NC}"

# --- Step 3: Directory and Initial Nginx Setup ---
echo -e "\n${BLUE}--- Creating web directory and setting up Nginx... ---${NC}"
# Create the www directory in the root user's home
mkdir -p /root/www
# Set ownership to the web server user
chown -R www-data:www-data /root/www
echo -e "Created web directory at /root/www"

# Remove the default Nginx configuration
rm -f /etc/nginx/sites-enabled/default

# Create a temporary Nginx configuration for Certbot
cat >/etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN *.$DOMAIN;

    # This is just a temporary root for the server block to be valid
    root /var/www/html;
    index index.html;
}
EOF

# Enable the new configuration
ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# Test and reload Nginx
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
echo -e "4. Go back to the terminal and press [Enter] to let Certbot verify the record."
read -p "Press [Enter] to begin the interactive Certbot process..."

certbot certonly --manual --preferred-challenges=dns -d "$DOMAIN" -d "*.$DOMAIN"

# Check if the certificate was successfully created
if [ ! -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
  echo -e "${YELLOW}Certbot failed. The certificate was not created. Please review any error messages and try again. Exiting.${NC}"
  exit 1
fi

echo -e "${GREEN}SSL Certificate successfully obtained!${NC}"

# --- Step 5: Final Nginx Configuration for SSL and Dynamic Subdomains ---
echo -e "\n${BLUE}--- Applying final Nginx configuration for SSL and dynamic subdomains... ---${NC}"

# Overwrite the previous configuration file with the final, dynamic one
cat >/etc/nginx/sites-available/$DOMAIN <<EOF
# This server block handles the root domain (e.g., TEJL.com)
# You can change the root path if you want a separate site for it.
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    root /root/www/root; # Example: create a /root/www/root folder for the main site
    index index.html;

    # SSL configuration from Certbot
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

# This server block dynamically handles all subdomains (e.g., blog.TEJL.com)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    # Regex to capture the subdomain part of the hostname
    server_name ~^(?<subdomain>.+)\.$DOMAIN$;

    # Use the captured subdomain to set the document root
    root /root/www/\$subdomain;
    index index.html;

    # SSL configuration from Certbot
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

# Redirect all HTTP traffic to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN *.$DOMAIN;

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

# Test and reload Nginx with the final configuration
nginx -t
systemctl reload nginx
echo -e "${GREEN}Final Nginx configuration has been applied.${NC}"

# --- Step 6: Create Renewal Information File ---
echo -e "\n${BLUE}--- Creating renewal information file... ---${NC}"

cat >/root/certbot-renewal-information.txt <<EOF
# =========================================================
# SSL Certificate Renewal Information for $DOMAIN
# =========================================================

Your wildcard SSL certificate was generated using Certbot's "manual" method with a DNS challenge.
This method CANNOT be automated by the standard 'certbot renew' command.

You must manually renew the certificate before it expires (every 90 days).

To renew, run the following command and follow the on-screen instructions to update the DNS TXT record again:

certbot renew --force-renewal

It is recommended to do this about a week before the certificate expires.
You can check the expiry date of your certificate with:

openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN/cert.pem
EOF

echo -e "${GREEN}Renewal information saved to /root/certbot-renewal-information.txt${NC}"

# --- Final Summary ---
echo -e "\n${GREEN}============================= SETUP COMPLETE! ==============================${NC}"
echo -e "Your server is now configured to serve dynamic subdomains."
echo -e "To add a new site, simply create a new folder inside the ${BLUE}/root/www/${NC} directory."
echo -e "For example:"
echo -e "  ${YELLOW}mkdir /root/www/blog${NC}"
echo -e "  ${YELLOW}echo '<h1>Hello from the blog!</h1>' > /root/www/blog/index.html${NC}"
echo -e "  ${YELLOW}chown -R www-data:www-data /root/www/blog${NC}"
echo -e "Then navigate to https://blog.${DOMAIN} in your browser."
echo ""
echo -e "${YELLOW}IMPORTANT: Remember to manually renew your SSL certificate. See the instructions in /root/certbot-renewal-information.txt${NC}"
echo -e "${GREEN}==========================================================================${NC}"
