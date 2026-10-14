{ pkgs, pythonEnv }:

pkgs.singularity-tools.buildImage {
  name = "nix-openmpi-python";

  # Packages whose /bin binaries will be symlinked into /bin inside the SIF container
  contents = [
    pythonEnv
    pkgs.mpi
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.stdenv.cc.cc.lib
  ];

  # Using pkgs.writeScript provides full path context to writeStringReferencesToFile
  runScript = pkgs.writeScript "runscript.sh" ''
    #!/bin/sh
    exec /bin/bash "$@"
  '';

  # Commands executed as root inside the VM before assembling the container image
  runAsRoot = ''
    # Create mount point directories for HPC filesystems
    mkdir -p /app /scratch /tmp
  '';

  # VM size constraints during construction
  diskSize = 10240;
  memSize = 4096;
}
