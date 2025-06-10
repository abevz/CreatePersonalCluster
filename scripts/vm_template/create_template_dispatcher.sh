#!/bin/bash

# VM Template Creation Dispatcher
# This script determines the OS type and calls the appropriate OS-specific template creation script
# Replaces the monolithic create_template_helper.sh with a modular approach

# Record the start time
start_time_total=$(date +%s)

# Import shared functions
# Auto-detect if running locally (with REPO_PATH) or remotely (relative paths)
if [[ -n "$REPO_PATH" ]]; then
    # Running locally via cpc - use REPO_PATH
    source "$REPO_PATH/scripts/vm_template/shared/common_functions.sh"
    SCRIPT_BASE_PATH="$REPO_PATH/scripts/vm_template"
else
    # Running remotely on Proxmox host - use relative paths
    source "$(dirname "$0")/shared/common_functions.sh"
    SCRIPT_BASE_PATH="$(dirname "$0")"
fi

main() {
    echo -e "${GREEN}Starting VM Template Creation Dispatcher...${ENDCOLOR}"
    
    # Step 1: Install required tools
    if ! install_required_tools; then
        echo -e "${RED}Failed to install required tools. Exiting.${ENDCOLOR}"
        exit 1
    fi
    
    # Step 2: Load environment and secrets
    if ! load_environment; then
        echo -e "${RED}Failed to load environment. Exiting.${ENDCOLOR}"
        exit 1
    fi
    
    # Step 3: Validate environment variables
    if ! validate_environment; then
        echo -e "${RED}Environment validation failed. Exiting.${ENDCOLOR}"
        exit 1
    fi
    
    # Step 4: Setup GPU tags if needed
    setup_gpu_tags
    
    # Step 5: Determine OS type from IMAGE_NAME
    local os_type=""
    if [[ "$IMAGE_NAME" == *"ubuntu"* || "$IMAGE_NAME" == *"Ubuntu"* ]]; then
        os_type="ubuntu"
    elif [[ "$IMAGE_NAME" == *"debian"* || "$IMAGE_NAME" == *"Debian"* ]]; then
        os_type="debian"
    elif [[ "$IMAGE_NAME" == *"Rocky"* || "$IMAGE_NAME" == *"rocky"* ]]; then
        os_type="rocky"
    elif [[ "$IMAGE_NAME" == *"suse"* || "$IMAGE_NAME" == *"SUSE"* || "$IMAGE_NAME" == *"openSUSE"* ]]; then
        os_type="suse"
    else
        echo -e "${RED}Error: Unable to determine OS type from IMAGE_NAME: $IMAGE_NAME${ENDCOLOR}"
        echo -e "${RED}Supported OS types: ubuntu, debian, rocky, suse${ENDCOLOR}"
        exit 1
    fi
    
    echo -e "${BLUE}Detected OS type: $os_type${ENDCOLOR}"
    
    # Step 6: Check if OS-specific script exists
    local os_script="$SCRIPT_BASE_PATH/${os_type}/create_${os_type}_template.sh"
    if [[ ! -f "$os_script" ]]; then
        echo -e "${RED}Error: OS-specific script not found: $os_script${ENDCOLOR}"
        echo -e "${YELLOW}Falling back to legacy create_template_helper.sh...${ENDCOLOR}"
        
        # Fallback to original script if OS-specific script doesn't exist
        if [[ -f "$SCRIPT_BASE_PATH/create_template_helper.sh" ]]; then
            exec "$SCRIPT_BASE_PATH/create_template_helper.sh"
        else
            echo -e "${RED}Error: Neither OS-specific script nor legacy script found. Exiting.${ENDCOLOR}"
            exit 1
        fi
    fi
    
    # Step 7: Make OS-specific script executable and run it
    chmod +x "$os_script"
    echo -e "${GREEN}Executing OS-specific template creation script: $os_script${ENDCOLOR}"
    
    # Export necessary variables for the OS-specific script
    export start_time_total
    export os_type
    
    # Execute the OS-specific script
    if "$os_script"; then
        echo -e "${GREEN}OS-specific template creation completed successfully.${ENDCOLOR}"
        print_elapsed_time "$start_time_total"
        echo -e "${GREEN}Template created successfully${ENDCOLOR}"
        exit 0
    else
        echo -e "${RED}OS-specific template creation failed.${ENDCOLOR}"
        exit 1
    fi
}

# Show usage information
usage() {
    echo "VM Template Creation Dispatcher"
    echo ""
    echo "This script automatically detects the OS type from IMAGE_NAME and calls"
    echo "the appropriate OS-specific template creation script."
    echo ""
    echo "Supported OS types:"
    echo "  - Ubuntu (ubuntu-*)"
    echo "  - Debian (debian-*)"
    echo "  - Rocky Linux (Rocky-*, rocky-*)"
    echo "  - SUSE/openSUSE (suse-*, SUSE-*, openSUSE-*)"
    echo ""
    echo "Usage: $0"
    echo ""
    echo "All required variables should be set via environment variables:"
    echo "  - IMAGE_NAME (determines OS type)"
    echo "  - All variables from cpc.env"
    echo "  - All secrets from SOPS"
    echo ""
    echo "This script is typically called by the main template.sh script."
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        # No arguments, proceed with main function
        main
        ;;
    *)
        echo "Unknown argument: $1"
        usage
        exit 1
        ;;
esac
