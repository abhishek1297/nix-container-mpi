[
  (
    final: prev:
    let
      # nixpkgs only provides OpenMPI 5.0.x which causes a lot installation conflicts with its predecessor
      # Instead, we directly create a new package here
      openmpi418 = prev.callPackage ./openmpi418.nix { };
    in
    {
      # Expose custom OpenMPI 4.1.8 as default mpi
      mpi = openmpi418;

      # Force mpi4py to compile against custom OpenMPI 4.1.8
      python3Packages = prev.python3Packages.overrideScope (
        pyFinal: pyPrev: {
          mpi4py = pyPrev.mpi4py.override {
            mpi = openmpi418;
          };
        }
      );
    }
  )
]
