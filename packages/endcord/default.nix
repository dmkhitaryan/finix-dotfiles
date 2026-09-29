{
  lib,
  python314Packages,
  fetchFromGitHub,
  makeWrapper,
  clang,
  lld,
  rnnoise,
}:

let
  pythonPackages = python314Packages.overrideScope (
    final: prev: {
      numpy =
        (prev.numpy.overridePythonAttrs (old: {
          buildInputs = [ ];
          preBuild = "";

          mesonFlags = (old.mesonFlags or [ ]) ++ [
            "-Dblas=none"
            "-Dlapack=none"
          ];
        })).overrideAttrs
          (old: {
            nativeBuildInputs = builtins.filter (pkg: !(lib.hasInfix "gfortran" (lib.getName pkg))) (
              old.nativeBuildInputs or [ ]
            );
          });

      soundcard = prev.soundcard.overridePythonAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace soundcard/pulseaudio.py \
            --replace-fail \
              'assert self._pa_context_get_state(self.context) == _pa.PA_CONTEXT_READY' \
              $'if self._pa_context_get_state(self.context) != _pa.PA_CONTEXT_READY:\n            raise RuntimeError("PulseAudio context not ready (no sound system?)")'
        '';
      });
    }
  );

  davepy = pythonPackages.callPackage ../davepy { };

  runtimeDeps =
    (with pythonPackages; [
      websocket-client
      python-socks
      orjson
      soundcard
      soundfile
      numpy
      pycryptodome
      pygments

      av
      pillow
      pynacl
    ])
    ++ [
      davepy
    ];
in

pythonPackages.buildPythonApplication (finalAttrs: {
  pname = "endcord";
  version = "1.5.4";

  pyproject = false;

  src = fetchFromGitHub {
    owner = "sparklost";
    repo = "endcord";
    tag = finalAttrs.version;
    hash = "sha256-ccpTm573Nhxj2AKvqSunE2ZZAemgox9hDakUSwvaw3s=";
  };

  build-system = with pythonPackages; [
    setuptools
    wheel
    cython
  ];

  nativeBuildInputs = [
    clang
    lld
    makeWrapper
  ];

  propagatedBuildInputs = runtimeDeps;

  buildPhase = ''
    runHook preBuild

    export CC=clang
    export CXX=clang++

    python setup.py build_ext --inplace

    # Upstream expects this next to the Endcord sources.
    cp ${lib.getLib rnnoise}/lib/librnnoise.so \
      endcord/librnnoise.so

    # Same compression upstream performs before packaging.
    python - <<'PY'
    import build
    import shutil

    path = build.compress_emoji()
    if path:
        shutil.copyfile(path, "endcord/emoji.json")
    PY

    rm -f endcord_cython/*.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/endcord" "$out/bin"

    cp main.py "$out/share/endcord/"
    cp -r endcord "$out/share/endcord/"
    cp -r endcord_cython "$out/share/endcord/"

    makeWrapper ${pythonPackages.python.interpreter} "$out/bin/endcord" \
      --add-flags "$out/share/endcord/main.py" \
      --prefix PYTHONPATH : "$out/share/endcord:${pythonPackages.makePythonPath runtimeDeps}" \
      --prefix PATH : ${
        lib.makeBinPath [
          pythonPackages.pygments
        ]
      }

    runHook postInstall
  '';

  doCheck = false;

  meta = {
    description = "Feature rich Discord TUI client";
    homepage = "https://github.com/sparklost/endcord";
    mainProgram = "endcord";
    platforms = lib.platforms.linux;
  };
})
