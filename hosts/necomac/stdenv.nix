# Clang stdenv for `config.replaceStdenv`. Clang itself is built by the gcc set.
{cpu}: {pkgs}: let
  inherit (pkgs) lib llvmPackages;
  clangCC = pkgs.clangStdenv.cc;

  rustHook = builtins.replaceStrings ["@cpu@"] [cpu] (builtins.readFile ./rust-hook.sh);

  # Builds that find windres try to compile Windows resources and crash.
  bintools = llvmPackages.bintools.override {
    bintools = llvmPackages.bintools-unwrapped.overrideAttrs (old: {
      buildCommand =
        old.buildCommand
        + "\n"
        + ''
          rm -f $out/bin/windres $out/bin/*-windres
        '';
    });
  };
in
  pkgs.overrideCC pkgs.clangStdenv (clangCC.override (old: {
    cc =
      clangCC.cc
      // {
        libgcc = pkgs.stdenv.cc.cc.libgcc;
        # Picked up by overlays/llvm.nix.
        bootLlvm = llvmPackages;
      };
    inherit bintools;
    extraBuildCommands =
      (old.extraBuildCommands or "")
      + ''
        # lld rejects version scripts naming missing symbols.
        echo "--undefined-version" >> $out/nix-support/cc-ldflags
        echo ${lib.escapeShellArg rustHook} >> $out/nix-support/setup-hook
      '';
  }))
