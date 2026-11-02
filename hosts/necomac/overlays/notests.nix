final: prev: let
  inherit (prev) lib;
  inherit (import ./lib.nix lib) noCheck testsOff;

  pythonPackageOverrides = _: pyPrev: let
    noTests =
      testsOff
      // {
        checkInputs = [];
        nativeCheckInputs = [];
      };

    wrapBuilder = builder: args:
      if builtins.isFunction args
      then builder (finalAttrs: (args finalAttrs) // noTests)
      else builder (args // noTests);
  in {
    buildPythonPackage = wrapBuilder pyPrev.buildPythonPackage;
    buildPythonApplication = wrapBuilder pyPrev.buildPythonApplication;
  };
in {
  #coreutils = noCheck prev.coreutils;
  jemalloc = noCheck prev.jemalloc;
  openapv = noCheck prev.openapv;
  glslang = noCheck prev.glslang;
  wget = noCheck prev.wget;
  handlr-regex = noCheck prev.handlr-regex;
  sqlite = prev.sqlite.overrideAttrs testsOff;
  nh-unwrapped = prev.nh-unwrapped.overrideAttrs (testsOff // {nativeCheckInputs = [];});

  spandsp = prev.spandsp.overrideAttrs (old: {
    checkPhase =
      builtins.replaceStrings
      ["ademco_contactid_tests|dtmf_rx_tests"]
      ["ademco_contactid_tests|modem_echo_tests|dtmf_rx_tests"]
      old.checkPhase;
  });

  python313 = prev.python313.override {
    packageOverrides = pythonPackageOverrides;
  };

  python314 = prev.python314.override {
    packageOverrides = pythonPackageOverrides;
  };

  # ShellCheck is Haskell, so a full GHC build.
  writeShellApplication = args:
    prev.writeShellApplication (
      {
        checkPhase = ''
          runHook preCheck
          ${prev.stdenv.shellDryRun} "$target"
          runHook postCheck
        '';
      }
      // args
    );
}
