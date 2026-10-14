{
  lib,
  stdenv,
  fetchurl,
  openssh,
  perl,
  zlib,
  numactl,
  libevent,
  hwloc,
  pmix,
  ucx,
  ucc,
  libnl,
  rdma-core,
  makeWrapper,
  gfortran ? null,
  fortranSupport ? true,
}:

stdenv.mkDerivation rec {
  pname = "openmpi";
  version = "4.1.8";

  src = fetchurl {
    url = "https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${version}.tar.bz2";
    hash = "sha256-Rm9o4xMqHcAnEMwgEfr87YM22YNZ+i2uTd3P1XGfEqk=";
  };

  postPatch = ''
    patchShebangs ./
  '';

  nativeBuildInputs = [
    perl
    makeWrapper
    openssh
  ]
  ++ lib.optionals fortranSupport [ gfortran ];

  buildInputs = [
    zlib
    libevent
    hwloc
    pmix
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    libnl
    numactl
  ]
  ++ lib.optionals (lib.meta.availableOn stdenv.hostPlatform ucx) [
    ucx
    ucc
  ]
  ++ lib.optionals (stdenv.hostPlatform.isLinux || stdenv.hostPlatform.isFreeBSD) [ rdma-core ];

  configureFlags = [
    "--enable-shared"
    "--enable-mpi1-compatibility"
    "--disable-oshmem" # Disables OSHMem to fix GCC 14 memheap brace errors
    "--enable-mca-no-build=mtl-ofi" # Disables OFI component to bypass GCC 13/14 inlining recursion errors
    "--with-pmix=${lib.getDev pmix}"
    "--with-pmix-libdir=${lib.getLib pmix}/lib"
    "--with-libevent=${lib.getDev libevent}"
    "--with-hwloc=${lib.getDev hwloc}"
    (lib.enableFeature fortranSupport "mpi-fortran")
  ];

  enableParallelBuilding = true;

  postInstall = ''
    # Remove static libtool files
    find $out/lib/ -name "*.la" -exec rm -f {} \;

    # Fix the MCA agent pathing lookup crash globally
    mkdir -p $out/etc
    echo "plm_rsh_agent = " >> $out/etc/openmpi-mca-params.conf
  '';

  meta = with lib; {
    description = "Open MPI 4.1.8 (built for host ABI compatibility)";
    homepage = "https://www.open-mpi.org/";
    license = licenses.bsd3;
    platforms = platforms.unix;
  };
}
