#!/bin/sh
#
# This script manages the init and renewal of SSL certificates using Certbot with Cloudflare DNS.
# 
# https://certbot-dns-cloudflare.readthedocs.io/en/stable/
# https://eff-certbot.readthedocs.io/en/stable/using.html#certbot-commands

echo "Starting Certbot Manager..."

# Function to handle graceful shutdown
cleanup() {
    echo "Shutting down certbot manager..."
    exit 0
}

# Set up signal handling
trap cleanup TERM INT

# Check if certificate exists, if not, create it
if [ ! -f /etc/letsencrypt/live/tecronin.uk/fullchain.pem ]; then
    echo "No certificate found, obtaining initial certificate..."
    
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials /cloudflare.ini \
        --dns-cloudflare-propagation-seconds 15 \
        --email tecronin@gmail.com \
        --agree-tos \
        --no-eff-email \
        --keep-until-expiring \
        -d tecronin.uk \
        -d *.tecronin.uk
    
    if [ $? -eq 0 ]; then
        echo "Initial certificate obtained successfully!"
    else
        echo "Failed to obtain initial certificate!"
        exit 1
    fi
else
    echo "Certificate already exists, skipping initial acquisition."
fi

# Start renewal loop
echo "Starting renewal monitoring..."
while true; do
    echo "$(date): Checking for certificate renewal..."
    
    # Run certbot renew (only renews if needed)
    certbot renew \
        --dns-cloudflare \
        --dns-cloudflare-credentials /cloudflare.ini \
        --quiet
    
    if [ $? -eq 0 ]; then
        echo "$(date): Certificate renewal check completed successfully"
    else
        echo "$(date): Certificate renewal check failed"
    fi
    
    echo "$(date): Sleeping for 12 hours..."
    
    # Sleep for 12 hours with signal handling
    sleep 43200 &
    wait $!
done