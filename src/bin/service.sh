#!/bin/bash

# service.sh - Create or delete the nginx config conf.d symlink for a service
# assumes the serive_name is the directory at /mnt/raid/service and under the directory
# is the nginx service_name.conf file
# Usage: ./service.sh -c|--create|-d|--delete service_name

# Display help message
show_help() {
    echo "Usage: $0 <action> <service_name>"
    echo
    echo "Actions:"
    echo "  -c, --create    Create a symlink from source_file to target_link"
    echo "  -d, --delete    Delete the symlink at target_link"
    echo "  -h, --help      print this help message"
    echo
    echo "Examples:"
    echo "  $0 --create nexus"
    echo "  $0 -d nexus"
    exit 1
}

# Check if we have enough arguments
if [ "$#" -lt 2 ]; then
    show_help
fi

SERVICE_NAME="$2"
SERVICE_DIR="/mnt/raid/services/$SERVICE_NAME"
CONF_FILE="$SERVICE_DIR/$SERVICE_NAME.conf"
TARGET="/mnt/raid/services/nginx/.conf.d/$SERVICE_NAME.conf"

if [ ! -d "$SERVICE_DIR" ]; then
    echo "Error: $SERVICE_DIR does not exist"
    exit 1
fi

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: $CONF_FILE does not exist"
    exit 1
fi

# Process based on the action parameter
case "$1" in
    -c|--create)
        
        # Create the symlink
        cp "$CONF_FILE" "$TARGET"
        
        if [ $? -eq 0 ]; then
            echo "Successfully copied file from '$CONF_FILE' to '$TARGET'"
        else
            echo "Failed to copy file"
            exit 1
        fi
        ;;
        
    -d|--delete)
        
        # Check if the target exists and is a symlink
        if [ -f "$TARGET" ]; then
            # Delete the symlink
            rm -f "$TARGET"
            
            if [ $? -eq 0 ]; then
                echo "Successfully deleted file '$TARGET'"
            else
                echo "Failed to delete symlink"
                exit 1
            fi
        fi
        ;;
        
    -h|--help)
        show_help
        ;;
        
    *)
        echo "Error: Unknown action '$1'"
        show_help
        ;;
esac

exit 0