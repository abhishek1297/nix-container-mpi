#!/bin/bash

#SBATCH --account=igf@cpu
#SBATCH --job-name=nix-mpi-test
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --time=00:05:00
#SBATCH --output=mpi_diag.out
#SBATCH --error=mpi_diag.err

module purge
module load singularity openmpi/4.1.8

NIX_CONTAINER="$SINGULARITY_ALLOWED_DIR/nix-openmpi-python.sif"

# Site-specific mounts for Jean-Zay (Pass as argument to resolver)
JZ_BASE_MOUNTS="$PWD,/gpfslocalsup,/gpfslocalsys,/lib64/slurm,/var/run,/etc/libibverbs.d,/etc/libnl"

# Dynamically resolve dependencies
source ./resolve_host_mpi_deps.sh "$JZ_BASE_MOUNTS"

echo "Running MPI Diagnostics across ${SLURM_NTASKS} ranks..."

# 1. Sanity check shared library preloading
srun -n 1 --mpi=pmix_v3 singularity exec "$NIX_CONTAINER" python3 -c "import ctypes; print(ctypes.CDLL('/host/openmpi/lib/libmpi.so'))"
srun --mpi=pmix_v3 singularity exec "$NIX_CONTAINER" python3 diagnostics.py

# 2. Default Run (PSM2)
echo "Running Default Benchmark..."
srun --mpi=pmix_v3 singularity exec "$NIX_CONTAINER" python3 benchmark.py

# 3. OmniPath (PSM2) Run
echo "Running OmniPath Benchmark..."
SINGULARITYENV_OMPI_MCA_pml="cm" \
SINGULARITYENV_OMPI_MCA_mtl="psm2" \
SINGULARITYENV_OMPI_MCA_mtl_base_verbose=100 \
srun --mpi=pmix_v3 singularity exec "$NIX_CONTAINER" python3 benchmark.py

# 4. TCP Run (Passing hardvalue for the subnet to avoid tcp hangs)
echo "Running TCP Benchmark..."
SINGULARITYENV_OMPI_MCA_pml=ob1 \
SINGULARITYENV_OMPI_MCA_btl=self,vader,tcp \
SINGULARITYENV_OMPI_MCA_btl_tcp_if_include=10.159.8.0/24 \
SINGULARITYENV_OMPI_MCA_btl_base_verbose=100 \
srun --mpi=pmix_v3 -n 2 singularity exec "$NIX_CONTAINER" python3 benchmark.py

