{
  lib,
  python314Packages,
  fetchPypi,
}:

python314Packages.buildPythonPackage (finalAttrs: {
  pname = "dave-py";
  version = "1.0.0";

  format = "wheel";

  src = fetchPypi {
    pname = "dave_py";
    inherit (finalAttrs) version;

    format = "wheel";
    dist = "cp314";
    python = "cp314";
    abi = "cp314";
    platform = "musllinux_1_2_aarch64";

    hash = "sha256-63aXDpz1c9EYt8qXxkchxyGhvkexXPiUWcatCQjxr/M=";
  };

  pythonImportsCheck = [
    "dave"
  ];

  meta = {
    description = "Python bindings for Discord's libdave";
    homepage = "https://github.com/DisnakeDev/dave.py";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [
      binaryNativeCode
    ];
    platforms = [ "aarch64-linux" ];
  };
})
