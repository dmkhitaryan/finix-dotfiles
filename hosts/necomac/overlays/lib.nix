lib: rec {
  # Early bootstrap stages have no compiler.
  isClang = pkgs: (pkgs.stdenv.cc or null) != null && (pkgs.stdenv.cc.isClang or false);

  testsOff = {
    doCheck = false;
    doInstallCheck = false;
  };
  noCheck = pkg: pkg.overrideAttrs {doCheck = false;};

  # Helpers to filter out and drop packages/etc.
  dropNamed = names: lib.filter (p: !(lib.isDerivation p && lib.elem (lib.getName p) names));
  dropPkgs = pkgs: lib.filter (p: !(lib.elem p pkgs));
  dropOutputs = names: lib.filter (o: !(lib.elem o names));

  replaceFlags = prefixes: extra: flags:
    lib.filter (f: !(lib.any (p: lib.hasPrefix p f) prefixes)) flags ++ extra;

  addCflags = flags: pkg:
    pkg.overrideAttrs (old: {
      env =
        (old.env or {})
        // {
          NIX_CFLAGS_COMPILE = toString (old.env.NIX_CFLAGS_COMPILE or "") + " " + flags;
        };
    });

  useBasu =
    replaceFlags
    ["-Dsd-bus-provider=" "-Dsystemd="]
    ["-Dsd-bus-provider=basu" "-Dsystemd=disabled"];
}
