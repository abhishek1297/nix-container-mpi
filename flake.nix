{
  description = "Decomposed Nix container environment for host OpenMPI ABI compatibility";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = import ./overlays.nix;
        };

        pythonEnv = pkgs.python3.withPackages (ps: [
          ps.mpi4py
          ps.numpy
        ]);

      in
      {
        packages = {
          default = pythonEnv;

          container = import ./container.nix {
            inherit pkgs pythonEnv;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pythonEnv
            pkgs.mpi
          ];

          shellHook = ''
            echo "=================================================="
            echo " OpenMPI Nix Development Shell Loaded"
            echo " MPI Version : $(mpirun --version | head -n 1)"
            echo " mpi4py Path : $(python3 -c 'import mpi4py; print(mpi4py.__file__)')"
            echo "=================================================="
          '';
        };
      }
    );
}
