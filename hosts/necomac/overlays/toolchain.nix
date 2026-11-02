# Clang-only set of overrides.
# Outside the clang set every name is the unchanged original.
final: prev: let
  inherit (prev) lib;
  inherit (import ./lib.nix lib) isClang noCheck addCflags;

  clangOnly = lib.mapAttrs (name: patch:
    if isClang prev
    then patch prev.${name}
    else prev.${name});

  # Build rustc's std for the host only, drop wasm/BPF targets.
  rustcHostOnly = rprev: {
    rustc-unwrapped = rprev.rustc-unwrapped.overrideAttrs (old: {
      configureFlags =
        map (
          flag:
            if lib.hasPrefix "--target=" flag
            then
              "--target="
              + lib.concatStringsSep "," (
                lib.filter (t:
                  !lib.elem t [
                    "wasm32-unknown-unknown"
                    "wasm32v1-none"
                    "bpfel-unknown-none"
                    "bpfeb-unknown-none"
                  ])
                (lib.splitString "," (lib.removePrefix "--target=" flag))
              )
            else flag
        )
        (old.configureFlags or []);
    });
  };

  patchRustSet = r:
    r
    // {
      packages =
        r.packages
        // {
          stable = r.packages.stable.overrideScope (_: rustcHostOnly);
        };
    };

  rustSets = lib.filterAttrs (n: _: builtins.match "rust_[0-9]+_[0-9]+" n != null) prev;
in
  clangOnly {
    doctest = pkg:
      pkg.overrideAttrs (old: {
        doCheck = false;
        cmakeFlags = (old.cmakeFlags or []) ++ ["-DDOCTEST_WITH_TESTS=OFF"];
      });

    diffutils = noCheck;
    gnutls = noCheck;

    # Reuse the coreutils that stdenv already ships in initialPath.
    # Do not build another one with clang.
    coreutils = _: lib.findFirst (p: (p.pname or "") == "coreutils") prev.coreutils prev.stdenv.initialPath;

    # Kbuild hardcodes HOSTCC=gcc; nixpkgs only patches
    # that for cross-compile builds.
    busybox = pkg:
      (pkg.override {extraConfig = ''CONFIG_DIFF n CONFIG_CMP n'';}).overrideAttrs (old: {
        patches =
          (old.patches or [])
          ++ [(prev.path + "/pkgs/os-specific/linux/busybox/clang-cross.patch")];
      });

    # Nim defaults to gcc on Linux.
    nim-unwrapped = pkg:
      pkg.overrideAttrs (old: {
        postConfigure =
          (old.postConfigure or "")
          + ''
            echo 'cc = clang' >> config/nim.cfg
          '';
      });

    expect = addCflags "-Wno-error=incompatible-pointer-types";

    # musl doesn't pull these headers in.
    cyrus_sasl = addCflags "-include time.h";
    bubblewrap = addCflags "-include limits.h";

    # musl's ioctl vs libv4l2's v4l2_ioctl.
    ffmpeg = pkg:
      pkg.overrideAttrs (old: {
        configureFlags =
          (old.configureFlags or [])
          ++ ["--extra-cflags=-Wno-error=incompatible-function-pointer-types"];
      });

    # cc-wrapper's --target warning breaks expected-output tests.
    haskellPackages = hs:
      hs.override (old: {
        overrides = lib.composeExtensions (old.overrides or (_: _: {})) (_: hprev: {
          doctest = prev.haskell.lib.dontCheck hprev.doctest;
        });
      });

    # No standalone `as` in LLVM bintools.
    libaom = pkg:
      pkg.overrideAttrs (old: {
        cmakeFlags = (old.cmakeFlags or []) ++ ["-DCMAKE_ASM_COMPILER=cc"];
      });
  }
  // clangOnly (lib.mapAttrs (_: _: patchRustSet) rustSets)
  // {
    netbsd = prev.netbsd.overrideScope (_: nprev: {
      fts =
        if isClang prev
        then
          nprev.fts.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + "\n"
              + ''
                sed -i '/#include <ssp\/ssp.h>/d' lib/libc/include/namespace.h
              '';
          })
        else nprev.fts;
    });
  }
