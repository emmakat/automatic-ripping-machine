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

# Check if we're in the right directory
if [ ! -d "$HANDBRAKE_DIR" ]; then
    log_error "HandBrake directory not found. Please run from directory containing HandBrake folder."
fi

# Step 1: Install ALL possible CUDA packages aggressively
log_info "Installing EVERY available CUDA package..."
sudo apt update

# Try to install CUDA from multiple sources
CUDA_PACKAGES=(
    "cuda-toolkit-12-*"
    "cuda-compiler-12-*"
    "cuda-nvvm-dev-12-*"
    "cuda-nvrtc-dev-12-*"
    "cuda-driver-dev-12-*"
    "cuda-nvcc-12-*"
    "cuda-cudart-dev-12-*"
    "libcuda1"
    "libnvidia-ml-dev"
    "nvidia-cuda-dev"
    "libnvvm-dev"
    "cuda-runtime-12-*"
)

for package in "${CUDA_PACKAGES[@]}"; do
    sudo apt install -y "$package" 2>/dev/null && log_info "✅ Installed: $package" || log_warning "❌ Failed: $package"
done

# Step 2: Manually install CUDA Toolkit if not present
if [ ! -d "/usr/local/cuda" ] && [ ! -d "/usr/local/cuda-12" ]; then
    log_info "No CUDA installation found. Installing CUDA Toolkit manually..."
    
    # Download CUDA installer
    CUDA_INSTALLER="cuda_12.6.3_560.35.05_linux.run"
    CUDA_URL="https://developer.download.nvidia.com/compute/cuda/12.6.3/local_installers/$CUDA_INSTALLER"
    
    cd /tmp
    if ! wget "$CUDA_URL" 2>/dev/null; then
        log_warning "Could not download CUDA installer - using repository packages only"
    else
        # Install CUDA toolkit (toolkit only, no drivers)
        chmod +x "$CUDA_INSTALLER"
        sudo sh "$CUDA_INSTALLER" --silent --toolkit --no-opengl-libs
        rm -f "$CUDA_INSTALLER"
        log_success "CUDA Toolkit installed manually"
    fi
    cd - > /dev/null
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
export CUDA_ROOT="$CUDA_ROOT"
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
