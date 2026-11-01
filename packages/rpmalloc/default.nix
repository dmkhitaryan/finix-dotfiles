{
  lib,
  stdenv,
  src,
  version ? "2.0.1",
}:
stdenv.mkDerivation {
  pname = "rpmalloc";
  inherit src version;
  dontConfigure = true;

  env.NIX_CFLAGS_COMPILE = toString [
    "-O3"
    "-D_GNU_SOURCE"
    "-DBUILD_DYNAMIC_LINK=1"
    "-DENABLE_DYNAMIC_LINK=1"
    # "-DENABLE_UNMAP=0"
    # "-DENABLE_DECOMMIT=0"
  ];

  buildPhase = ''
    runHook preBuild
    $CC -fPIC -shared -Wl,-soname,librpmalloc.so -pthread \
      -Irpmalloc rpmalloc/rpmalloc.c -o librpmalloc.so
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 librpmalloc.so $out/lib/librpmalloc.so
    install -Dm644 rpmalloc/rpmalloc.h $out/include/rpmalloc.h
    runHook postInstall
  '';

  meta.platforms = lib.platforms.linux;
}
