# Hosting Automator Script [DEPRECATED]

This repo is now deprecated and moved into github.com/Eris-Margeta/tools for easier maintenance and discovery


This repository contains a shell script, `hosting-automator.sh`, designed to automate the setup of a Debian server to host multiple static websites on dynamic subdomains. It uses Nginx for the web server and secures all sites with a single, wildcard Let's Encrypt SSL certificate.

The core principle of this setup is "convention over configuration". To launch a new website at `subdomain.yourdomain.com`, you simply create a new directory named `subdomain` in your web root folder.

## Features

-   **Fully Automated Setup**: Installs and configures Nginx, Certbot, and UFW firewall.
-   **Dynamic Subdomains**: Automatically serves content based on the directory name.
-   **Wildcard SSL**: Secures the root domain and all subdomains with a single Let's Encrypt certificate.
-   **Interactive Guidance**: Pauses and provides clear instructions for the manual DNS steps required for wildcard certificates.
-   **Secure by Default**: Configures the firewall and forces HTTPS on all traffic.
-   **Post-Setup Instructions**: Creates a `.txt` file on the server with instructions for the manual SSL renewal process.

## Prerequisites

1.  A server running a fresh installation of **Debian 11 or Debian 12**.
2.  You must be logged in as the **`root`** user.
3.  A registered **domain name** that you own.
4.  Access to your domain's **DNS settings** (e.g., at Hetzner, GoDaddy, Cloudflare, etc.).
5.  `git` must be installed (`apt install git -y`).

## How to Use

Log into your Debian server as the `root` user via SSH.

### One-Line Command

For the fastest setup, run this single command. It will clone the repository, make the script executable, and run it.

```bash
git clone https://github.com/Eris-Margeta/hosting-automator.git && cd hosting-automator && chmod +x hosting-automator.sh && ./hosting-automator.sh
```

The script will then ask for your domain name and server IP address and will guide you through the rest of the process.

### Step-by-Step Instructions

If you prefer to run the commands individually, you can follow these steps:

**1. Clone the repository:**
```bash
git clone https://github.com/Eris-Margeta/hosting-automator.git
```

**2. Navigate into the directory:**
```bash
cd hosting-automator
```

**3. Make the script executable:**```bash
chmod +x hosting-automator.sh
```

**4. Run the script:**
```bash
./hosting-automator.sh
```

## After the Script Finishes

Your server is ready to host websites. To add a new site, simply create a new folder in the `/root/www/` directory and set the correct ownership.

For example, to create a new website accessible at `portfolio.yourdomain.com`:

```bash
# 1. Create the directory for your new site
mkdir /root/www/portfolio

# 2. Add your website files (e.g., an index.html)
echo '<h1>Welcome to my portfolio!</h1>' > /root/www/portfolio/index.html

# 3. Set ownership so the web server can read the files
chown -R www-data:www-data /root/www/portfolio
```

That's it! You can now visit `https://portfolio.yourdomain.com` in your browser.

## A Note on SSL Renewal

Because this setup uses a wildcard certificate, the renewal process **cannot be fully automated**. You must manually intervene every 90 days to prove domain ownership by creating a new DNS TXT record.

Detailed instructions for this process are saved on your server in the following file:
`/root/certbot-renewal-information.txt`

It is highly recommended that you set a calendar reminder to renew your certificate about 80 days after setup.
