#!/bin/bash
set -e

log_info() {
    echo -e "\n\e[1;34mINFO: $1\e[0m"
}

log_success() {
    echo -e "\n\e[1;32mSUCCESS: $1\e[0m"
}

log_error() {
    echo -e "\n\e[1;31mERROR: $1\e[0m"
    exit 1
}

log_warning() {
    echo -e "\n\e[1;33mWARNING: $1\e[0m"
}

HANDBRAKE_DIR="HandBrake"

echo "========================================================================"
echo "Builds Handbrake with NVENC and CUDA LLVM support for ARM installations with a compatible RTX GPU"
echo "========================================================================"

# NEW: Function to get latest HandBrake version
get_latest_handbrake_version() {
    log_info "Finding current HandBrake version"
    local handbrake_version
    # More robust parsing for version number
    handbrake_version=$(curl --silent 'https://github.com/HandBrake/HandBrake/releases' | grep -oP 'HandBrake/tree/\K[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -z "$handbrake_version" ]; then
        handbrake_version="1.8.2"  # fallback
        log_warning "Could not determine latest HandBrake version, falling back to $handbrake_version"
    fi
    echo "$handbrake_version"
}

# NEW: Function to get latest CUDA version
get_latest_cuda_version() {
    log_info "Finding current CUDA version"
    local cuda_version
    # Try to get from NVIDIA downloads page
    cuda_version=$(curl --silent "https://developer.nvidia.com/cuda-downloads" | grep -oE 'CUDA Toolkit [0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')
    if [ -z "$cuda_version" ]; then
        cuda_version="12.6.3"  # fallback
        log_warning "Could not determine latest CUDA version, falling back to $cuda_version"
    fi
    echo "$cuda_version"
}

# NEW: Function to get compatible driver version
get_compatible_driver_version() {
    local cuda_version="$1"
    case "$cuda_version" in
        "12.6.3"|"12.6.2"|"12.6.1"|"12.6.0") echo "560.35.05" ;;
        "12.5.1"|"12.5.0") echo "555.42.06" ;;
        "12.4.1"|"12.4.0") echo "550.54.15" ;;
        "12.3.2"|"12.3.1"|"12.3.0") echo "545.23.08" ;;
        *) echo "560.35.05" ;;  # safe fallback
    esac
}

# NEW: Download and verify HandBrake if directory doesn't exist
if [ ! -d "$HANDBRAKE_DIR" ]; then
    HANDBRAKE_VERSION=$(get_latest_handbrake_version)
    log_info "Downloading HandBrake $HANDBRAKE_VERSION"
    
    # Download source and signature
    wget -O handbrake.tar.bz2.sig "https://github.com/HandBrake/HandBrake/releases/download/$HANDBRAKE_VERSION/HandBrake-$HANDBRAKE_VERSION-source.tar.bz2.sig" || log_error "Failed to download HandBrake signature"
    wget -O handbrake.tar.bz2 "https://github.com/HandBrake/HandBrake/releases/download/$HANDBRAKE_VERSION/HandBrake-$HANDBRAKE_VERSION-source.tar.bz2" || log_error "Failed to download HandBrake source"
    
    # Verify signature
    # https://handbrake.fr/openpgp.php or https://github.com/HandBrake/HandBrake/wiki/OpenPGP
    GNUPGHOME="$(mktemp -d)" && export GNUPGHOME
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys '1629 C061 B3DD E7EB 4AE3  4B81 021D B8B4 4E4A 8645' || log_error "Failed to retrieve GPG key"
    gpg --batch --verify handbrake.tar.bz2.sig handbrake.tar.bz2 || log_error "HandBrake signature verification failed"
    rm -rf "$GNUPGHOME" handbrake.tar.bz2.sig
    
    # Extract HandBrake
    mkdir -p "$HANDBRAKE_DIR"
    tar --extract \
        --file handbrake.tar.bz2 \
        --directory "$HANDBRAKE_DIR" \
        --strip-components 1 \
        "HandBrake-$HANDBRAKE_VERSION" || log_error "Failed to extract HandBrake source"
    rm handbrake.tar.bz2
    
    log_success "HandBrake $HANDBRAKE_VERSION downloaded and verified"
fi

# Check if we're in the right directory
if [ ! -d "$HANDBRAKE_DIR" ]; then
    log_error "HandBrake directory not found. Please run from directory containing HandBrake folder."
fi

# Step 1: Install ALL possible CUDA packages aggressively
log_info "Installing EVERY available CUDA package..."
sudo apt update

# Get the major CUDA version dynamically for apt packages
CURRENT_CUDA_MAJOR_VERSION=$(get_latest_cuda_version | cut -d'.' -f1)
if [ -z "$CURRENT_CUDA_MAJOR_VERSION" ]; then
    CURRENT_CUDA_MAJOR_VERSION="12" # Fallback if detection fails
    log_warning "Could not determine current CUDA major version for apt packages, falling back to $CURRENT_CUDA_MAJOR_VERSION"
fi

# Try to install CUDA from multiple sources, using the dynamically determined major version
CUDA_PACKAGES=(
    "cuda-toolkit-${CURRENT_CUDA_MAJOR_VERSION}-*"
    "cuda-compiler-${CURRENT_CUDA_MAJOR_VERSION}-*"
    "cuda-nvvm-dev-${CURRENT_CUDA_MAJOR_VERSION}-*"
    "cuda-nvrtc-dev-${CURRENT_CUDA_MAJOR_VERSION}-*"
    "cuda-driver-dev-${CURRENT_CUDA_MAJOR_VERSION}-*"
    "cuda-nvcc-${CURRENT_CUDA_MAJOR_VERSION}-*"
    "cuda-cudart-dev-${CURRENT_CUDA_MAJOR_VERSION}-*"
    "libcuda1"
    "libnvidia-ml-dev"
    "nvidia-cuda-dev"
    "libnvvm-dev"
    "cuda-runtime-${CURRENT_CUDA_MAJOR_VERSION}-*"
)

for package in "${CUDA_PACKAGES[@]}"; do
    # Removed 2>/dev/null to show apt output during installation attempts
    if sudo apt install -y "$package"; then
        log_info "✅ Installed: $package"
    else
        log_warning "❌ Failed: $package (See apt output above for details)"
    fi
done

# Step 2: Manually install CUDA Toolkit if not present (UPDATED for dynamic version)
if [ ! -d "/usr/local/cuda" ] && [ ! -d "/usr/local/cuda-12" ]; then
    log_info "No CUDA installation found. Installing latest CUDA Toolkit..."
    
    # NEW: Get latest CUDA version dynamically
    CUDA_VERSION=$(get_latest_cuda_version)
    DRIVER_VERSION=$(get_compatible_driver_version "$CUDA_VERSION")
    
    CUDA_INSTALLER="cuda_${CUDA_VERSION}_${DRIVER_VERSION}_linux.run"
    CUDA_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/$CUDA_INSTALLER"
    CUDA_CHECKSUM_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/$CUDA_INSTALLER.sha256"
    
    log_info "Downloading CUDA $CUDA_VERSION with driver $DRIVER_VERSION"
    
    cd /tmp
    
    # Download CUDA installer (removed 2>/dev/null to show progress/errors)
    if ! wget "$CUDA_URL"; then
        log_warning "Could not download latest CUDA installer. Continuing with repository packages only."
        cd - > /dev/null
    else
        # Try to download and verify checksum
        log_info "Verifying CUDA installer integrity..."
        if wget "$CUDA_CHECKSUM_URL" -O "$CUDA_INSTALLER.sha256"; then
            # Verify SHA256 checksum
            if sha256sum -c "$CUDA_INSTALLER.sha256"; then
                log_success "CUDA installer checksum verified"
            else
                log_warning "CUDA installer checksum verification failed, but continuing..."
            fi
            rm -f "$CUDA_INSTALLER.sha256"
        else
            log_warning "Could not download CUDA checksum, skipping verification"
        fi
        
        # Install CUDA toolkit (toolkit only, no drivers)
        chmod +x "$CUDA_INSTALLER"
        if sudo sh "$CUDA_INSTALLER" --silent --toolkit --no-opengl-libs; then
            log_success "CUDA $CUDA_VERSION installed manually"
        else
            log_error "CUDA installation failed"
        fi
        rm -f "$CUDA_INSTALLER"
        cd - > /dev/null
    fi
fi

# Step 3: Find and configure CUDA paths aggressively
log_info "Configuring CUDA paths..."

# Find CUDA installation
CUDA_PATHS=(
    "/usr/local/cuda"
    "/usr/local/cuda-12"
    "/usr/local/cuda-12.6"
    "/usr/local/cuda-12.5"
    "/usr/local/cuda-12.4"
)

CUDA_ROOT=""
for path in "${CUDA_PATHS[@]}"; do
    if [ -d "$path" ]; then
        CUDA_ROOT="$path"
        log_success "Found CUDA at: $CUDA_ROOT"
        break
    fi
done

if [ -z "$CUDA_ROOT" ]; then
    # Create symlink if CUDA exists elsewhere
    if [ -d "/usr/lib/nvidia-cuda-toolkit" ]; then
        sudo ln -sf /usr/lib/nvidia-cuda-toolkit /usr/local/cuda
        CUDA_ROOT="/usr/local/cuda"
        log_info "Created CUDA symlink"
    else
        log_error "No CUDA installation found anywhere"
    fi
fi

# Step 4: Set up environment variables
log_info "Setting up CUDA environment..."

export CUDA_HOME="$CUDA_ROOT"
export CUDA_PATH="$CUDA_ROOT"
export PATH="$CUDA_ROOT/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_LIBRARY_PATH="$CUDA_ROOT/lib64:$CUDA_ROOT/nvvm/lib64:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"
export NVCC_PREPEND_FLAGS='-ccbin /usr/bin/gcc'

# Add to system configuration
echo "# CUDA Configuration" | sudo tee /etc/ld.so.conf.d/cuda.conf > /dev/null
echo "$CUDA_ROOT/lib64" | sudo tee -a /etc/ld.so.conf.d/cuda.conf > /dev/null
echo "$CUDA_ROOT/nvvm/lib64" | sudo tee -a /etc/ld.so.conf.d/cuda.conf > /dev/null
sudo ldconfig

# Step 5: Verify CUDA LLVM components
log_info "Verifying CUDA LLVM components..."

# Check NVCC
if command -v nvcc &> /dev/null; then
    NVCC_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/')
    log_success "NVCC version: $NVCC_VERSION"
else
    log_error "NVCC still not found after installation"
fi

# Check NVVM library
NVVM_FOUND=false
NVVM_PATHS=(
    "$CUDA_ROOT/nvvm/lib64/libnvvm.so"
    "/usr/lib/x86_64-linux-gnu/libnvvm.so"
    "/usr/local/lib/libnvvm.so"
)

for path in "${NVVM_PATHS[@]}"; do
    if [ -f "$path" ]; then
        log_success "Found NVVM library: $path"
        NVVM_FOUND=true
        break
    fi
done

if [ "$NVVM_FOUND" = false ]; then
    log_error "NVVM library not found. CUDA LLVM will not work."
fi

# Step 6: Force HandBrake rebuild with CUDA LLVM
log_info "Force rebuilding HandBrake with CUDA LLVM..."

cd "$HANDBRAKE_DIR"

# Clean completely
make --directory=build clean 2>/dev/null || true
rm -rf build

# Remove any patches that disable CUDA LLVM
if [ -f "contrib/ffmpeg/module.defs.backup" ]; then
    mv contrib/ffmpeg/module.defs.backup contrib/ffmpeg/module.defs
    log_info "Restored original FFmpeg configuration"
fi

# Configure with FORCE CUDA LLVM
log_info "Configuring with FORCED CUDA LLVM support..."
echo ""
echo "Environment variables:"
echo "CUDA_PATH=$CUDA_PATH"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "PATH=$PATH"
echo ""

if ./configure --disable-gtk --enable-nvenc --enable-nvdec --launch-jobs=$(nproc) --force 2>&1 | tee configure_cuda.log; then
    log_success "Configure completed"
    
    # Check what was actually detected
    echo ""
    echo "=== CONFIGURE DETECTION RESULTS ==="
    grep -i "cuda\|nvenc\|llvm" configure_cuda.log || echo "No CUDA mentions found"
    echo ""
    
    # Check build configuration
    if [ -f "build/GNUmakefile" ]; then
        echo "=== BUILD CONFIGURATION ==="
        grep -i "cuda\|nvenc" build/GNUmakefile | head -10 || echo "No CUDA in makefile"
        echo ""
    fi
    
    # Try building
    log_info "Building with CUDA LLVM (this may take 30+ minutes)..."
    if make --directory=build 2>&1 | tee build_cuda.log; then
        
        # Check if CUDA LLVM was actually used
        if grep -q "cuda.*llvm\|enable.*cuda" build_cuda.log; then
            log_success "🎉 BUILD SUCCEEDED WITH CUDA LLVM!"
        else
            log_warning "Build succeeded but unclear if CUDA LLVM was used"
        fi
        
        # Install
        sudo make --directory=build install
        
        # Test
        log_info "Testing NVENC with CUDA LLVM..."
        if HandBrakeCLI --help 2>&1 | grep -q "nvenc: version"; then
            log_success "NVENC is working!"
            
            # Show what we built
            echo ""
            echo "=== FINAL VERIFICATION ==="
            HandBrakeCLI --help 2>&1 | head -10
            echo ""
            HandBrakeCLI --help 2>&1 | grep -A 10 "Select video encoder" | grep nvenc
            echo ""
            
        else
            log_error "NVENC not detected in final build"
        fi
        
    else
        log_error "Build failed even with forced CUDA LLVM"
        echo ""
        echo "=== BUILD ERROR LOG ==="
        tail -50 build_cuda.log
    fi
    
else
    log_error "Configure failed"
    echo ""
    echo "=== CONFIGURE ERROR LOG ==="
    tail -20 configure_cuda.log
fi

cd - > /dev/null

log_info "CUDA LLVM force installation completed"
echo ""
echo "Log files created:"
echo "  - HandBrake/configure_cuda.log"
echo "  - HandBrake/build_cuda.log"
echo ""
echo "If CUDA LLVM still didn't work, check these logs for specific errors."
