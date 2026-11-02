# musl with ARM's optimized string functions
# (github.com/ARM-software/optimized-routines).
#
# This overlay also reaches the bootstrap stages, so every stdenv (gcc and
# clang) uses this musl as its libc. The stock glibc imports in apps.nix don't.
#
# TODO: decide on what to do memcpy + memmove, as they need more handling.
final: prev: let
  sources = import ../../../.tack;
  optimizedRoutines = sources.optimized-routines;
in {
  musl = prev.musl.overrideAttrs (old: {
    # System-wide preload file, /etc/ld-musl-<arch>.preload.
    patches = (old.patches or []) ++ [../../../patches/musl-preload-file.patch];

    postPatch =
      (old.postPatch or "")
      + ''
        # musl builds src/string/aarch64/<name>.S instead of <name>.c if present.
        # ARM calls its functions __<name>_aarch64, so for each one we write a
        # two-line file there: rename to <name>, then include ARM's file.
        d=src/string/aarch64
        mkdir -p $d/or
        cp ${optimizedRoutines}/string/aarch64/asmdefs.h $d/or/
        for f in memchr memcmp memset strlen strnlen strchr strrchr strcmp strncmp strcpy; do
          cp ${optimizedRoutines}/string/aarch64/$f.S $d/or/
          printf '#define __%s_aarch64 %s\n#include "or/%s.S"\n' $f $f $f > $d/$f.S
        done
      '';
  });
}
