# Portable MPI Container with Nix Flakes & Singularity

A clean, reproducible template for building containerized Python/MPI applications using Nix Flakes and native Singularity/Apptainer tools on HPC clusters (`slurm` + `PMIx`).

This repository leverages **MPI ABI compatibility**: compiling `mpi4py` inside the container against an exact version match of OpenMPI (v4.1.8) allows it to dynamically swap in the host cluster's native high-speed network drivers (InfiniBand, UCX, RoCE) and Slurm/PMIx environment at runtime using `LD_PRELOAD`.

## Repository Layout

```
.
├── flake.nix                  # Flake entry point & development shell
├── overlays.nix               # OpenMPI & mpi4py package overrides
├── openmpi418.nix             # Standalone OpenMPI 4.1.8 derivation
├── container.nix              # Native Singularity SIF image definition
├── diagnostics.py             # Diagnostic script to verify MPI rank topology & host linking
├── benchmark.py               # Basic benchmark to test the interconnect speed within the container
├── resolve_host_mpi_deps.sh   # Generic script to bind MPI depepdencies on the cluster.
└── jz.slurm                   # Slurm submission wrapper script for jean-zay
```

## Quick Start

### 1. Build the Singularity Image Native (`.sif`)

Compile the Python environment and output a Singularity image directly using Nix:

```bash
nix build .#container
```

### 2. Enter Development Shell (Optional)

For local testing, interactive debugging, or development:

```bash
nix develop
```

### 3. Run on Slurm Cluster

Transfer `result` (or copy the generated `.sif` image) to your HPC environment and submit. [jz.slurm](jz.slurm) showcases runs a diagnostics program on Jean-Zay.

> The container is working on jean-zay, maintaining binary compatibility and using OmniPath (psm2) interconnect between nodes correctly.

## Technical Workflow & Cluster Integration

When launching the container under Slurm, host network drivers (InfiniBand/UCX/OFI), parallel filesystems (Lustre/GPFS), and vendor runtime libraries (Intel/NVIDIA) must be passed through to the container.

To achieve high-speed interconnect performance without breaking the container’s Nix-provided C runtime, the submission workflow dynamically inspects host dependencies and binds them cleanly at runtime.

### Dynamic Integration Strategy

[resolve_host_mpi_deps.sh](./resolve_host_mpi_deps.sh) is a resuable cluster-agnostic script that can be used for dynamically binding host-specific paths required for MPI dependencies.

1. **Directories outside system paths** (e.g., vendor compiler runtimes or site modules) are mounted in full to dedicated isolated targets (e.g., `/host/dep_N`).

2. **Individual library files residing in system `/usr/lib64`** (e.g., `liblustreapi.so.1`) are bound specifically as single files (e.g., `/host/system_libs/liblustreapi.so.1`) rather than mounting the host's `/usr/lib64` directory.

3. **Automated `ldd` Resolution**: Instead of manually searching for cluster-specific shared objects, the job submission script inspects the host's active `libmpi.so` via `ldd` and constructs mount bindings on the fly.

4. **Runtime Preloading & Environment Forwarding**: The host's native `libmpi.so` is force-loaded via `LD_PRELOAD`, while Slurm/PMIx variables are passed into the Singularity environment.

## Troubleshooting

### 1. `glibc` Symbol Conflicts (`GLIBC_PRIVATE`)

* **Issue:** Mounting `/usr/lib64` or host `libc.so.6` inside the container causes symbol mismatches with container binaries.
* **Fix:** Isolate host dependencies into `/host/...` paths and bind individual system libraries (e.g., `liblustreapi.so.1`) instead of mounting system library directories. All processes run on the container's backward-compatible Nix `glibc`.

### 2. OpenMPI ABI Mismatches

* **Issue:** OpenMPI guarantees ABI compatibility only within the same minor release series (e.g., 4.1.x to 4.1.y), failing across major boundaries (e.g., 4.x vs 5.x).

* **Fix:** Ensure the OpenMPI derivation inside your Nix Flake matches the cluster's native OpenMPI major/minor release series (e.g., pin 4.1.x in `overlays.nix` if the host uses 4.1.8).

### 3. SIF Build Storage Exhaustion (`No space left on device`)

* **Issue:** `singularity-tools.buildImage` constructs images inside a QEMU virtual machine whose default 2 GB disk fills up rapidly when copying compiler and MPI dependencies.

* **Fix:** Allocate sufficient resources in `container.nix` (e.g., `diskSize = 10240;` MB) and wrap startup scripts with `pkgs.writeScript` to ensure derivation store paths resolve cleanly.

## Architectural Trade-Offs & Host Interop Realities

Bridging a hermetic container with a host's MPI stack presents a fundamental tension: **application reproducibility vs. hardware performance**. Injecting host drivers (`libmpi.so`, `libucx`) dynamically breaks container isolation, leaving the runtime vulnerable to driver ABI drifts, missing system plugins, and non-standard cluster configurations.

Furthermore, low-level process management (PMIx) and hardware transports rely on host shared memory (`/dev/shm`), hardware devices (`/dev/infiniband`), and system sockets. Bypassing container namespace isolation is often mandatory to prevent lock failures, which introduces cluster-specific debugging overhead whenever target hardware or MPI build flags change.

Selective host-library binding is a pragmatic compromise—delivering near-native HPC performance without rebuilding application stacks—but it remains an active trade-off rather than a zero-configuration, universal solution.