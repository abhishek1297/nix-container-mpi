#!/bin/bash
# ==============================================================================
# Dynamic Host MPI Dependency Resolver for Nix/Singularity Containers
# ==============================================================================
# Usage:
#   source ./resolve_host_mpi_deps.sh [/optional/extra/mounts]
#
# Generates:
#   - SINGULARITY_BIND
#   - SINGULARITYENV_LD_LIBRARY_PATH
#   - SINGULARITYENV_LD_PRELOAD
# ==============================================================================

# 1. Locate host OpenMPI library directory dynamically
HOST_MPI_LIB=$(mpicc --showme:libdirs 2>/dev/null | awk '{print $1}')
if [ -z "$HOST_MPI_LIB" ]; then
    HOST_MPI_LIB=$(echo "${LD_LIBRARY_PATH}" | tr ':' '\n' | grep -i 'openmpi' | head -n1)
fi

if [ -z "$HOST_MPI_LIB" ] || [ ! -f "${HOST_MPI_LIB}/libmpi.so" ]; then
    echo "Error: Could not locate host libmpi.so. Ensure an MPI module is loaded." >&2
    return 1 2>/dev/null || exit 1
fi

# 2. Extract dynamic shared library dependencies via ldd
HOST_DEP_FILES=$(ldd "${HOST_MPI_LIB}/libmpi.so" 2>/dev/null \
    | awk '/=>/ {print $3}' \
    | grep '^/' \
    | grep -vE '/libc\.so|/libpthread\.so|/librt\.so|/libdl\.so|/libm\.so|/ld-linux|/nix/store')

BIND_MOUNTS="${HOST_MPI_LIB}:/host/openmpi/lib:ro"
CONTAINER_LD_PATHS="/host/openmpi/lib"

idx=1
for lib_path in $HOST_DEP_FILES; do
    dir=$(dirname "$lib_path")
    
    # Single-file mounts for system libraries to protect container glibc
    if [[ "$dir" == "/usr/lib64" || "$dir" == "/lib64" ]]; then
        lib_name=$(basename "$lib_path")
        BIND_MOUNTS="${BIND_MOUNTS},${lib_path}:/host/system_libs/${lib_name}:ro"
        if [[ ":$CONTAINER_LD_PATHS:" != *":/host/system_libs:"* ]]; then
            CONTAINER_LD_PATHS="${CONTAINER_LD_PATHS}:/host/system_libs"
        fi
    else
        # Directory mounts for isolated vendor runtimes (Intel, UCX, etc.)
        target_mount="/host/dep_${idx}"
        if [[ ":$CONTAINER_LD_PATHS:" != *":${target_mount}:"* ]]; then
            BIND_MOUNTS="${BIND_MOUNTS},${dir}:${target_mount}:ro"
            CONTAINER_LD_PATHS="${CONTAINER_LD_PATHS}:${target_mount}"
            idx=$((idx + 1))
        fi
    fi
done

# 3. Incorporate any cluster-specific base mounts passed as an argument
EXTRA_MOUNTS="${1:-$PWD,/var/run,/etc/libibverbs.d,/etc/libnl}"

# 4. Export resolved variables to Singularity runtime environment
export SINGULARITY_BIND="${EXTRA_MOUNTS},${BIND_MOUNTS}"
export SINGULARITYENV_LD_LIBRARY_PATH="${CONTAINER_LD_PATHS}"
export SINGULARITYENV_LD_PRELOAD="/host/openmpi/lib/libmpi.so"

# Forward Slurm/PMIx variables if present
for v in OMPI_MCA_pml OMPI_MCA_btl UCX_NET_DEVICES PMIX_NAMESPACE PMIX_RANK; do
    [ -n "${!v}" ] && export "SINGULARITYENV_${v}=${!v}"
done