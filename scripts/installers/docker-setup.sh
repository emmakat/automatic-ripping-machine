#!/usr/bin/env bash
set -eo pipefail

# Colors for better visual feedback
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
FORK="automaticrippingmachine"
TAG="latest"
HOST_PORT="8080"
CONTAINER_NAME="arm-rippers"

# Function to display script usage
function usage() {
    echo -e "\nUsage: docker_setup.sh [OPTIONS]"
    echo -e " -f <fork>\tSpecify the fork to pull from on DockerHub. \n\t\tDefault is \"$FORK\""
    echo -e " -t <tag>\tSpecify the tag to pull from on DockerHub. \n\t\tDefault is \"$TAG\""
    echo -e "\nThis script sets up the Automatic Ripping Machine (ARM) Docker environment."
    echo -e "It requires root privileges to run."
}

# Parse command-line options
while getopts 'f:t:' OPTION; do
    case $OPTION in
        f) FORK=$OPTARG ;;
        t) TAG=$OPTARG ;;
        ?) usage; exit 2 ;;
    esac
done

IMAGE="$FORK/automatic-ripping-machine:$TAG"

# Function to check for root privileges
function check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root or with sudo.${NC}"
        exit 1
    fi
}

# Function to install required system packages
function install_reqs() {
    echo -e "${RED}--- Installing required packages (curl, lsscsi) ---${NC}"
    apt update -y && apt install -y curl lsscsi
    echo -e "${GREEN}Required packages installed successfully.${NC}"
}

# Function to add the 'arm' user and group
function add_arm_user() {
    echo -e "${RED}--- Setting up 'arm' user and group ---${NC}"
    
    # Create arm group if it doesn't exist
    if ! getent group arm >/dev/null; then
        groupadd arm
        echo -e "${GREEN}arm group created.${NC}"
    else
        echo -e "${YELLOW}arm group already exists, skipping...${NC}"
    fi

    # Create arm user if it doesn't exist
    if ! id arm >/dev/null 2>&1; then
        useradd -m arm -g arm
        echo -e "${GREEN}arm user created.${NC}"
        
        # Ask if user wants to set a password
        echo
        read -p "Do you want to set a password for the 'arm' user? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            passwd arm
        else
            echo -e "${YELLOW}No password set for 'arm' user. You can set one later with 'sudo passwd arm'.${NC}"
        fi
    else
        echo -e "${YELLOW}arm user already exists, skipping...${NC}"
    fi
    
    usermod -aG cdrom,video arm
    echo -e "${GREEN}User 'arm' added to 'cdrom' and 'video' groups.${NC}"
}

# Function to install Docker and add 'arm' user to 'docker' group
function launch_setup() {
    echo -e "${RED}--- Checking for Docker and installing if needed ---${NC}"
    
    if [ -e /usr/bin/docker ]; then
        echo -e "${YELLOW}Docker installation detected, skipping installation...${NC}"
    else
        echo -e "${RED}Installing Docker...${NC}"
        curl -fsSL https://get.docker.com | bash
        echo -e "${GREEN}Docker installed successfully.${NC}"
    fi
    
    echo -e "${RED}Adding user 'arm' to docker group...${NC}"
    usermod -aG docker arm
    systemctl restart docker
    echo -e "${GREEN}User 'arm' added to docker group and Docker restarted.${NC}"
}

# Function to pull the ARM Docker image
function pull_image() {
    echo -e "${RED}--- Pulling Docker image: $IMAGE ---${NC}"
    su - arm -c "docker pull \"$IMAGE\""
    echo -e "${GREEN}Docker image pulled successfully.${NC}"
}

# Function to set up mount points for optical drives
function setup_mountpoints() {
    echo -e "${RED}--- Creating mount points for optical drives ---${NC}"
    
    local mount_count=0
    for device in /dev/sr*; do
        if [[ -e "$device" ]]; then
            MOUNT_POINT="/mnt$device"
            mkdir -p "$MOUNT_POINT"
            chown arm:arm "$MOUNT_POINT"
            echo -e "${GREEN}Created mount point: $MOUNT_POINT${NC}"
            mount_count=$((mount_count + 1))
        fi
    done
    
    if [ "$mount_count" -eq 0 ]; then
        echo -e "${YELLOW}No optical drives found for mount point creation.${NC}"
    else
        echo -e "${GREEN}Created $mount_count mount points.${NC}"
    fi
}

# Function to detect system configuration
function detect_system_config() {
    echo -e "${RED}--- Detecting system configuration ---${NC}"
    
    # Get ARM user details
    ARM_UID=$(id -u arm)
    ARM_GID=$(id -g arm)
    ARM_HOME=$(getent passwd arm | cut -d: -f6)
    TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
    
    # Create ARM directories
    mkdir -p "$ARM_HOME"/{music,logs,media,config}
    chown arm:arm "$ARM_HOME"/{music,logs,media,config}
    echo -e "${GREEN}ARM directories created and configured.${NC}"
    
    # Ask about NVIDIA support
    echo
    read -p "Do you have NVIDIA GPU with CUDA/NVENC support? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ENABLE_NVIDIA=true
        echo -e "${GREEN}NVIDIA GPU support will be enabled.${NC}"
    else
        ENABLE_NVIDIA=false
        echo -e "${YELLOW}NVIDIA GPU support disabled.${NC}"
    fi
    
    # Detect CPU cores (reserve core 0 for the system)
    TOTAL_CORES=$(nproc)
    if [[ "$TOTAL_CORES" -gt 1 ]]; then
        LAST_CORE_INDEX=$((TOTAL_CORES - 1))
        CPU_CORES=$(seq -s, 1 "$LAST_CORE_INDEX")
    else
        CPU_CORES="0"
    fi
    echo -e "${GREEN}Container will be pinned to CPU cores: $CPU_CORES${NC}"
}

# Function to detect optical devices
function detect_optical_devices() {
    echo -e "${RED}--- Detecting optical devices ---${NC}"
    
    OPTICAL_DEVICES=()
    
    # Use lsscsi to detect devices
    while IFS= read -r line; do
        if echo "$line" | grep -qE 'cd/dvd|rom'; then
            for device in $(echo "$line" | grep -oP '/dev/s[rg]\d+'); do
                if [[ -e "$device" && ! " ${OPTICAL_DEVICES[@]} " =~ " ${device} " ]]; then
                    OPTICAL_DEVICES+=("$device")
                fi
            done
        fi
    done < <(lsscsi -g 2>/dev/null || true)
    
    # Also check /dev/sr* directly
    for device in /dev/sr*; do
        if [[ -e "$device" ]] && udevadm info --query=property --name="$device" 2>/dev/null | grep -q 'ID_CDROM=1'; then
            if [[ ! " ${OPTICAL_DEVICES[@]} " =~ " ${device} " ]]; then
                OPTICAL_DEVICES+=("$device")
            fi
        fi
    done
    
    if [ ${#OPTICAL_DEVICES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No optical drives detected.${NC}"
    else
        echo -e "${GREEN}Detected optical drives: ${OPTICAL_DEVICES[*]}${NC}"
    fi
}

# Function to generate the container start script
function save_start_command() {
    START_SCRIPT="$ARM_HOME/start_arm_container.sh"
    echo -e "${RED}--- Generating start script at: $START_SCRIPT ---${NC}"
    
    # Backup existing script if it exists
    if [[ -e "$START_SCRIPT" ]]; then
        echo -e "${YELLOW}'start_arm_container.sh' already exists. Backing up...${NC}"
        mv "$START_SCRIPT" "$START_SCRIPT.bak"
    fi
    
    # Create the docker run script with populated values
    cat > "$START_SCRIPT" << EOF
#!/bin/bash
# This script was auto-generated by the ARM setup script.
# It contains the direct command to start the ARM Docker container.

docker run -d \\
    -p "$HOST_PORT:8080" \\
    -e PUID="$ARM_UID" \\
    -e PGID="$ARM_GID" \\
    -e TZ="$TIMEZONE" \\
    -v "$ARM_HOME/music:/home/arm/music" \\
    -v "$ARM_HOME/logs:/home/arm/logs" \\
    -v "$ARM_HOME/media:/home/arm/media" \\
    -v "$ARM_HOME/config:/etc/arm/config" \\
EOF
    
    # Add optical devices to the script
    for device in "${OPTICAL_DEVICES[@]}"; do
        echo "    --device=\"$device:$device\" \\" >> "$START_SCRIPT"
    done
    
    # Add NVIDIA support if enabled
    if [[ "$ENABLE_NVIDIA" == "true" ]]; then
        echo "    --gpus all \\" >> "$START_SCRIPT"
        echo "    -e NVIDIA_VISIBLE_DEVICES=all \\" >> "$START_SCRIPT"
        echo "    -e NVIDIA_DRIVER_CAPABILITIES=all \\" >> "$START_SCRIPT"
    fi
    
    # Add the rest of the command
    cat >> "$START_SCRIPT" << EOF
    --privileged \\
    --restart "always" \\
    --name "$CONTAINER_NAME" \\
EOF
    
    # Add CPU cores if available
    if [[ -n "$CPU_CORES" ]]; then
        echo "    --cpuset-cpus='$CPU_CORES' \\" >> "$START_SCRIPT"
    fi
    
    # Add the final image name
    echo "    \"$IMAGE\"" >> "$START_SCRIPT"
    
    chmod +x "$START_SCRIPT"
    chown arm:arm "$START_SCRIPT"
    
    echo -e "${GREEN}Start script generated successfully.${NC}"
}

# --- Main Execution Flow ---
check_root
install_reqs
add_arm_user
launch_setup
pull_image
setup_mountpoints
detect_system_config
detect_optical_devices
save_start_command

echo
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}        ARM Docker Setup Complete!        ${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}The start script has been created at: $START_SCRIPT${NC}"
echo
echo -e "${GREEN}To start the container, run:${NC}"
echo -e "${YELLOW}  sudo -u arm $START_SCRIPT${NC}"
echo
echo -e "${GREEN}To view container logs, run:${NC}"
echo -e "${YELLOW}  docker logs -f $CONTAINER_NAME${NC}"
echo
echo -e "${GREEN}To stop the container, run:${NC}"
echo -e "${YELLOW}  docker stop $CONTAINER_NAME${NC}"
echo -e "${GREEN}===========================================${NC}"
