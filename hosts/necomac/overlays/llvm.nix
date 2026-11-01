final: prev: let
  sources = import ../../../.tack;
  inherit (prev) lib;
  inherit (import ./lib.nix lib) isClang dropNamed;

  wildStdenv = let
    p = prev.stdenv;
    ok = plat: plat.isLinux && plat.isElf;
  in
    if
      ok p.buildPlatform
      && ok p.hostPlatform
      && ok p.targetPlatform
      && (p.cc.bintools ? override)
    then prev.useWildLinker p
    else p;

  targets =
    if prev.stdenv.hostPlatform.isx86_64
    then "X86;AMDGPU;"
    else if prev.stdenv.hostPlatform.isAarch64
    then "AArch64;"
    else throw "Add the LLVM backend list for this host architecture";

  # musl's fortify-headers approach blocks inlining; ~50% slower compiling.
  noFortify = old: (old.hardeningDisable or []) ++ ["fortify" "fortify3"];

  trim = llvmPkgs:
    llvmPkgs.overrideScope (
      self: llvmPrev: let
        libllvm =
          (llvmPrev.libllvm.override {
            enableManpages = false;
            enablePFM = false;
            enablePolly = false;
            enableTerminfo = false;

            devExtraCmakeFlags = [
              "-DLLVM_TARGETS_TO_BUILD=${targets}"
              "-DLLVM_BUILD_TESTS=OFF"
              "-DLLVM_INCLUDE_TESTS=OFF"
              "-DLLVM_INCLUDE_EXAMPLES=OFF"
              "-DLLVM_INCLUDE_BENCHMARKS=OFF"
            ];
          }).overrideAttrs
          (old: {
            buildInputs = dropNamed ["libffi" "libxml2"] (old.buildInputs or []);
            cmakeFlags = (old.cmakeFlags or []) ++ ["-DLLVM_ENABLE_FFI=OFF" "-DLLVM_ENABLE_LIBXML2=OFF"];

            doCheck = false;
            hardeningDisable = noFortify old;
          });

        libclang =
          (llvmPrev.libclang.override {
            stdenv = wildStdenv;
            inherit libllvm;
            enableClangToolsExtra = false;
            enableManpages = false;

            devExtraCmakeFlags = [
              "-DCLANG_ENABLE_OBJC_REWRITER=OFF"
              "-DCLANG_INCLUDE_TESTS=OFF"
            ];
          }).overrideAttrs
          (old: {
            doCheck = false;
            hardeningDisable = noFortify old;

            # Not using extra tools in Clang. Create empty stub.
            postInstall =
              ''
                touch $out/bin/run-clang-tidy
              ''
              + (old.postInstall or "");
          });
      in {
        inherit libllvm libclang;
        llvm = libllvm;
        clang-unwrapped = libclang;
        # Otherwise nixpkgs picks libc++ clang under the clang stdenv.
        clang = self.libstdcxxClang;
        # GDB plugin pulls libpython.
        openmp = llvmPrev.openmp.override {ompdGdbSupport = false;};
      }
    );

  trimOverridable = llvmPkgs:
    (trim llvmPkgs)
    // {
      override = args: trimOverridable (llvmPkgs.override args);
    };

  # Under clang, reuse the gcc stage's LLVM so we don't rebuild extra.
  llvm22 = let
    boot = prev.stdenv.cc.cc.bootLlvm or null;
  in
    if isClang prev && boot != null
    then boot
    else trimOverridable prev.llvmPackages_22;
in {
  llvmPackages_21 = trimOverridable prev.llvmPackages_21;
  llvmPackages_22 = llvm22;

  # Trying out https://github.com/mjansson/rpmalloc.
  rpmalloc = final.callPackage ../../../packages/rpmalloc {
    src = sources.rpmalloc;
  };

  # 16K pages: THP is 32 MiB, eats extra memory.
  mimalloc = prev.mimalloc.overrideAttrs (old: {
    env =
      (old.env or {})
      // {
        NIX_CFLAGS_COMPILE = toString (old.env.NIX_CFLAGS_COMPILE or "") + " -DMI_DEFAULT_ALLOW_THP=0";
      };
  });

  llvmPackages = llvm22;
}
