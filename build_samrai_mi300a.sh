#!/bin/bash
###############################################################################
# build_samrai_mi300a.sh
#
# End-to-end build script for SAMRAI targeting MI300A GPUs (gfx942) with HIP.
# Builds TPL dependencies (CAMP, Umpire, Proteus, RAJA JIT branch) then SAMRAI itself
# with HIP, RAJA, Umpire, and GPU-aware MPI (device allocators) enabled.
#
# Environment: TOSS 4 (Cray), ROCm 6.4.0, cray-mpich 8.1.31, CMake 3.29.2
#
# Usage:
#   ./build_samrai_mi300a.sh              # Full build (TPLs + SAMRAI)
#   ./build_samrai_mi300a.sh --tpl-only   # Build only TPL dependencies
#   ./build_samrai_mi300a.sh --samrai-only # Build only SAMRAI (TPLs must exist)
###############################################################################
set -e

# --------------------------------------------------------------------------- #
# Configuration — adjust these paths for your system
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAMRAI_SRC="${SCRIPT_DIR}"
BUILD_ROOT="${SCRIPT_DIR}/build_mi300a"
TPL_ROOT="${SCRIPT_DIR}/tpl_build_mi300a"
TPL_INSTALL=${TPL_ROOT}/install

CMAKE=/usr/tce/packages/cmake/cmake-3.29.2/bin/cmake

# ROCm / HIP
ROCM_VER=6.4.0
ROCM_PATH=/opt/rocm-${ROCM_VER}
ROCMCC=/usr/tce/packages/rocmcc-tce/rocmcc-${ROCM_VER}
CXX=${ROCMCC}/bin/amdclang++
CC=${ROCMCC}/bin/amdclang
FC=${ROCMCC}/bin/amdflang
GPU_ARCH=gfx942       # MI300A
LLVM_DIR=/opt/rocm-${ROCM_VER}/llvm
PROTEUS_PASS="${TPL_INSTALL}/proteus/lib64/libProteusPass.so"

# MPI (cray-mpich built against rocmcc)
MPI_ROOT=/usr/tce/packages/cray-mpich-tce/cray-mpich-8.1.31-rocmcc-${ROCM_VER}
MPICXX=${MPI_ROOT}/bin/mpicxx

# HIP compiler flags used for all TPLs and SAMRAI
HIP_FLAGS="-D__HIP_ROCclr__ -D__HIP_PLATFORM_AMD__ -DCAMP_USE_PLATFORM_DEFAULT_STREAM -std=c++17 -x hip --offload-arch=${GPU_ARCH}"

TPL_VERSION=2025.09.0
NPROC=$(nproc)
MAKE_JOBS=${MAKE_JOBS:-${NPROC}}

# --------------------------------------------------------------------------- #
# Parse arguments
# --------------------------------------------------------------------------- #
BUILD_TPLS=true
BUILD_SAMRAI=true
if [[ "$1" == "--tpl-only" ]]; then
    BUILD_SAMRAI=false
elif [[ "$1" == "--samrai-only" ]]; then
    BUILD_TPLS=false
fi

# --------------------------------------------------------------------------- #
# Helper
# --------------------------------------------------------------------------- #
log() {
    echo ""
    echo "======================================================================="
    echo "  $1"
    echo "======================================================================="
    echo ""
}

# --------------------------------------------------------------------------- #
# 1. Download TPL sources
# --------------------------------------------------------------------------- #
download_tpls() {
    log "Downloading TPL sources (v${TPL_VERSION})"
    mkdir -p "${TPL_ROOT}"
    cd "${TPL_ROOT}"

    # CAMP (needed separately — not bundled in RAJA release tarball)
    if [[ ! -f "camp-v${TPL_VERSION}.tar.gz" ]]; then
        wget "https://github.com/LLNL/camp/releases/download/v${TPL_VERSION}/camp-v${TPL_VERSION}.tar.gz"
    fi
    if [[ ! -d "camp" ]]; then
        tar xf "camp-v${TPL_VERSION}.tar.gz"
        mv "camp-v${TPL_VERSION}" camp
    fi

    # Umpire
    if [[ ! -f "umpire-${TPL_VERSION}.tar.gz" ]]; then
        wget "https://github.com/LLNL/umpire/releases/download/v${TPL_VERSION}/umpire-${TPL_VERSION}.tar.gz"
    fi
    if [[ ! -d "umpire" ]]; then
        tar xf "umpire-${TPL_VERSION}.tar.gz"
        mv "umpire-${TPL_VERSION}" umpire
    fi

    # RAJA (JIT branch — requires git clone instead of release tarball)
    if [[ ! -d "raja" ]]; then
        git clone --branch feature/bowen/enable-jit --single-branch --recurse-submodules \
            https://github.com/LLNL/RAJA.git raja
    fi

    # The RAJA branch may ship BLT without thirdparty_builtin.
    # Create a stub so BLT's unconditional add_subdirectory() doesn't fail.
    if [[ ! -d "raja/blt/thirdparty_builtin" ]]; then
        mkdir -p "raja/blt/thirdparty_builtin"
        echo "# Stub - not needed when tests are disabled" \
            > "raja/blt/thirdparty_builtin/CMakeLists.txt"
    fi

    # Proteus (JIT compiler for RAJA)
    if [[ ! -d "proteus" ]]; then
        git clone https://github.com/olympus-HPC/proteus.git proteus
    fi
}

# --------------------------------------------------------------------------- #
# 2. Build CAMP
# --------------------------------------------------------------------------- #
build_camp() {
    log "Building CAMP"
    local src="${TPL_ROOT}/camp"
    local build="${TPL_ROOT}/camp-build"
    local install="${TPL_INSTALL}/camp"

    rm -rf "${build}"
    mkdir -p "${build}"
    cd "${build}"

    ${CMAKE} "${src}" \
        -DCMAKE_CXX_COMPILER="${CXX}" \
        -DCMAKE_C_COMPILER="${CC}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${install}" \
        -DBLT_CXX_STD=c++17 \
        -DENABLE_TESTS=Off \
        -DENABLE_CUDA=Off \
        -DENABLE_HIP=On \
        -DROCM_PATH="${ROCM_PATH}" \
        -DHIP_ROOT_DIR="${ROCM_PATH}/hip" \
        -DHIP_HIPCC_FLAGS="${HIP_FLAGS}" \
        -DCMAKE_HIP_ARCHITECTURES="${GPU_ARCH}"

    make -j${MAKE_JOBS}
    make install

    rm -rf "${build}"
}

# --------------------------------------------------------------------------- #
# 3. Build Umpire
# --------------------------------------------------------------------------- #
build_umpire() {
    log "Building Umpire"
    local src="${TPL_ROOT}/umpire"
    local build="${TPL_ROOT}/umpire-build"
    local install="${TPL_INSTALL}/umpire"

    rm -rf "${build}"
    mkdir -p "${build}"
    cd "${build}"

    ${CMAKE} "${src}" \
        -DCMAKE_CXX_COMPILER="${CXX}" \
        -DCMAKE_C_COMPILER="${CC}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${install}" \
        -DBLT_CXX_STD=c++17 \
        -DCMAKE_CXX_STANDARD=17 \
        -DENABLE_CUDA=Off \
        -DENABLE_HIP=On \
        -DROCM_PATH="${ROCM_PATH}" \
        -DHIP_ROOT_DIR="${ROCM_PATH}/hip" \
        -DHIP_HIPCC_FLAGS="${HIP_FLAGS}" \
        -DCMAKE_HIP_ARCHITECTURES="${GPU_ARCH}" \
        -DENABLE_MPI=Off \
        -DENABLE_C=On \
        -DENABLE_FORTRAN=On \
        -DENABLE_OPENMP=Off \
        -DENABLE_EXAMPLES=Off \
        -DENABLE_TESTS=Off \
        -DENABLE_TOOLS=Off \
        -DENABLE_DOCS=Off \
        -DENABLE_BENCHMARKS=Off \
        -DUMPIRE_ENABLE_SLIC=Off \
        -DUMPIRE_ENABLE_LOGGING=On \
        -DUMPIRE_ENABLE_BACKTRACE=Off \
        -DUMPIRE_ENABLE_IPC_SHARED_MEMORY=Off \
        -Dcamp_DIR="${TPL_INSTALL}/camp/lib/cmake/camp"

    make -j${MAKE_JOBS}
    make install

    rm -rf "${build}"
}

# --------------------------------------------------------------------------- #
# 4. Build Proteus (JIT compiler for RAJA)
# --------------------------------------------------------------------------- #
build_proteus() {
    log "Building Proteus"
    local src="${TPL_ROOT}/proteus"
    local build="${TPL_ROOT}/proteus-build"
    local install="${TPL_INSTALL}/proteus"

    rm -rf "${build}"
    mkdir -p "${build}"
    cd "${build}"

    ${CMAKE} "${src}" \
        -DCMAKE_CXX_COMPILER="${CXX}" \
        -DCMAKE_C_COMPILER="${CC}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${install}" \
        -DLLVM_INSTALL_DIR="${LLVM_DIR}" \
        -DPROTEUS_ENABLE_HIP=On \
        -DPROTEUS_ENABLE_CUDA=Off \
        -DPROTEUS_ENABLE_MPI=On \
        -DMPI_CXX_COMPILER="${MPICXX}" \
        -DENABLE_TESTS=Off \
        -DBUILD_SHARED=Off

    make -j${MAKE_JOBS}
    make install

    rm -rf "${build}"
}

# --------------------------------------------------------------------------- #
# 5. Build RAJA
# --------------------------------------------------------------------------- #
build_raja() {
    log "Building RAJA"
    local src="${TPL_ROOT}/raja"
    local build="${TPL_ROOT}/raja-build"
    local install="${TPL_INSTALL}/raja"

    rm -rf "${build}"
    mkdir -p "${build}"
    cd "${build}"

    ${CMAKE} "${src}" \
        -DCMAKE_CXX_COMPILER="${CXX}" \
        -DCMAKE_C_COMPILER="${CC}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${install}" \
        -DBLT_CXX_STD=c++17 \
        -DCMAKE_CXX_STANDARD=17 \
        -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG" \
        -DENABLE_CUDA=Off \
        -DRAJA_ENABLE_CUDA=Off \
        -DENABLE_HIP=On \
        -DRAJA_ENABLE_HIP=On \
        -DROCM_PATH="${ROCM_PATH}" \
        -DHIP_ROOT_DIR="${ROCM_PATH}/hip" \
        -DHIP_HIPCC_FLAGS="${HIP_FLAGS}" \
        -DCMAKE_HIP_ARCHITECTURES="${GPU_ARCH}" \
        -DGPU_TARGETS="${GPU_ARCH}" \
        -DRAJA_ENABLE_HIP_INDIRECT_FUNCTION_CALL=On \
        -DRAJA_ENABLE_ROCTX=Off \
        -DENABLE_MPI=Off \
        -DENABLE_FORTRAN=Off \
        -DENABLE_OPENMP=Off \
        -DENABLE_TARGET_OPENMP=Off \
        -DENABLE_CLANG_CUDA=Off \
        -DENABLE_CHAI=Off \
        -DENABLE_EXAMPLES=Off \
        -DENABLE_TESTS=Off \
        -DENABLE_EXERCISES=Off \
        -DRAJA_ENABLE_EXERCISES=Off \
        -DRAJA_ENABLE_NESTED=Off \
        -DENABLE_DOCS=Off \
        -DENABLE_EXTERNAL_CUB=Off \
        -DRAJA_ENABLE_EXTERNAL_CUB=Off \
        -DBUILD_SHARED_LIBS=Off \
        -DENABLE_WARNINGS_AS_ERRORS=Off \
        -DENABLE_TBB=Off \
        -DRAJA_ENABLE_JIT=On \
        -DPROTEUS_INSTALL_DIR="${TPL_INSTALL}/proteus" \
        -Dcamp_DIR="${TPL_INSTALL}/camp/lib/cmake/camp"

    make -j${MAKE_JOBS}
    make install

    rm -rf "${build}"
}

# --------------------------------------------------------------------------- #
# 6. Ensure SAMRAI BLT submodule is initialized
# --------------------------------------------------------------------------- #
init_samrai_submodules() {
    log "Initializing SAMRAI submodules (BLT)"
    cd "${SAMRAI_SRC}"
    if [[ ! -f "blt/SetupBLT.cmake" ]]; then
        git submodule update --init blt
    fi
}

# --------------------------------------------------------------------------- #
# 7. Build SAMRAI
# --------------------------------------------------------------------------- #
build_samrai() {
    log "Configuring SAMRAI"
    mkdir -p "${BUILD_ROOT}"
    cd "${BUILD_ROOT}"

    ${CMAKE} "${SAMRAI_SRC}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_COMPILER="${CXX}" \
        -DCMAKE_C_COMPILER="${CC}" \
        -DCMAKE_Fortran_COMPILER="${FC}" \
        -DCMAKE_CXX_FLAGS="-std=c++17 --cuda-gpu-arch=${GPU_ARCH} -fpass-plugin=${PROTEUS_PASS}" \
        -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG" \
        -DENABLE_MPI=On \
        -DMPI_CXX_COMPILER="${MPICXX}" \
        -DENABLE_OPENMP=Off \
        -DENABLE_CUDA=Off \
        -DENABLE_HIP=On \
        -DROCM_PATH="${ROCM_PATH}" \
        -DHIP_ROOT_DIR="${ROCM_PATH}/hip" \
        -DHIP_HIPCC_FLAGS="${HIP_FLAGS}" \
        -DCMAKE_HIP_FLAGS="-fpass-plugin=${PROTEUS_PASS}" \
        -DCMAKE_HIP_ARCHITECTURES="${GPU_ARCH}" \
        -DGPU_TARGETS="${GPU_ARCH}" \
        -DAMDGPU_TARGETS="${GPU_ARCH}" \
        -DENABLE_UMPIRE=On \
        -DENABLE_RAJA=On \
        -DENABLE_SAMRAI_DEVICE_ALLOC=On \
        -Dcamp_DIR="${TPL_INSTALL}/camp/lib/cmake/camp" \
        -Dumpire_DIR="${TPL_INSTALL}/umpire/lib64/cmake/umpire" \
        -DRAJA_DIR="${TPL_INSTALL}/raja/lib/cmake/raja" \
        -Dproteus_DIR="${TPL_INSTALL}/proteus/lib64/cmake/proteus" \
        -DLLVM_DIR="${LLVM_DIR}/lib/cmake/llvm" \
        -DENABLE_CHECK_ASSERTIONS=Off \
        -DENABLE_TESTS=Off \
        -DBLT_CXX_STD=c++17 \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=On

    log "Building SAMRAI"
    make -j${MAKE_JOBS}

    # Verify all SAMRAI libraries were built
    local expected_libs="tbox hier pdat math geom mesh xfer algs solv appu"
    local missing=false
    for lib in ${expected_libs}; do
        if [[ ! -f "${BUILD_ROOT}/lib/libSAMRAI_${lib}.a" ]]; then
            echo "ERROR: libSAMRAI_${lib}.a not found!"
            missing=true
        fi
    done
    if ${missing}; then
        echo "FATAL: Some SAMRAI libraries failed to build."
        exit 1
    fi
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
if ${BUILD_TPLS}; then
    download_tpls
    build_camp
    build_umpire
    build_proteus
    build_raja
fi

if ${BUILD_SAMRAI}; then
    init_samrai_submodules
    build_samrai
fi

log "Build complete!"
echo "  TPL install:   ${TPL_INSTALL}"
echo "  SAMRAI build:  ${BUILD_ROOT}"
echo ""
echo "  GPU:           MI300A (${GPU_ARCH})"
echo "  ROCm:          ${ROCM_VER}"
echo "  LLVM:          ${LLVM_DIR}"
echo "  Compiler:      amdclang++ (rocmcc-${ROCM_VER})"
echo "  MPI:           cray-mpich 8.1.31"
echo "  RAJA:          JIT branch (feature/bowen/enable-jit)"
echo "  Proteus:       ${TPL_INSTALL}/proteus"
echo ""
echo "  ENABLE_SAMRAI_DEVICE_ALLOC=On: MPI buffers stay on device (GPU-aware MPI)"
echo "  RAJA_ENABLE_JIT=On: JIT compilation via Proteus"
echo "  To run tests: cd ${BUILD_ROOT} && ctest --output-on-failure"
echo ""
