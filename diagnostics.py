import ctypes
import os
import platform
import subprocess
import sys

from mpi4py import MPI


def get_pmix_version():
    """Attempt to extract the active PMIx version via C symbol lookup or ompi_info."""

    try:
        libmpi = ctypes.CDLL(None)
        if hasattr(libmpi, "PMIx_Get_version"):
            libmpi.PMIx_Get_version.restype = ctypes.c_char_p
            return libmpi.PMIx_Get_version().decode("utf-8")
    except Exception:
        pass

    try:
        out = subprocess.check_output(["ompi_info"], stderr=subprocess.DEVNULL).decode(
            "utf-8"
        )
        for line in out.splitlines():
            if "MCA pmix:" in line and "Component" in line:
                return line.split(":")[-1].strip()
    except Exception:
        pass

    return "Unknown (Embedded in OpenMPI MCA)"


def run_diagnostics():
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()
    processor_name = MPI.Get_processor_name()

    if rank == 0:
        print("=" * 60)
        print("               MPI CONTAINER DIAGNOSTICS")
        print("=" * 60)

        print("\n[1] ENVIRONMENT INFO")
        print(f"  Hostname (Rank 0)   : {processor_name}")
        print(f"  Python Version       : {platform.python_version()}")
        print(f"  Python Executable    : {sys.executable}")
        print(f"  Total MPI Ranks      : {size}")

        print("\n[2] MPI & PMIx IMPLEMENTATION DETAILS")
        vendor_name, vendor_version = MPI.get_vendor()
        print(
            f"  MPI Vendor           : {vendor_name} {'.'.join(map(str, vendor_version))}"
        )
        print(f"  MPI Standard Version : {MPI.Get_version()}")
        print(f"  PMIx Version         : {get_pmix_version()}")

        print("\n[3] DYNAMIC LINKING RESOLUTION")
        try:
            pid = os.getpid()
            maps = subprocess.check_output(["cat", f"/proc/{pid}/maps"]).decode("utf-8")
            mpi_libs = set(
                line.split()[-1] for line in maps.splitlines() if "libmpi.so" in line
            )

            print("  Active libmpi.so path(s) in memory:")
            for lib in mpi_libs:
                print(f"    -> {lib}")
        except Exception as e:
            print(f"  Could not parse /proc/PID/maps: {e}")

        print("\n[4] NETWORK & PMIx ENVIRONMENT")
        relevant_vars = {
            k: v
            for k, v in os.environ.items()
            if k.startswith(
                ("OMPI_", "PMIX_", "PMI_", "UCX_", "PML_", "BTL_", "SINGULARITY")
            )
        }
        if relevant_vars:
            for k, v in sorted(relevant_vars.items()):
                print(f"  {k} = {v}")
        else:
            print("  No explicit OMPI/PMIx/UCX environment variables set.")

        print("\n[5] CROSS-RANK COMMUNICATION TEST")

    all_hosts = comm.gather(processor_name, root=0)

    if rank == 0:
        for r, host in enumerate(all_hosts):
            print(f"  Rank {r:02d} running on node: {host}")
        print("=" * 60)


if __name__ == "__main__":
    run_diagnostics()
