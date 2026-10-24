# Limine for finix on Asahi, installed by a busybox shell script instead of
# finix's Python installer (modules/programs/limine/limine-install.py).
#
# Keeps the EFI boot path (m1n1 -> U-Boot -> bootefi Limine -> kernel), which
# the Asahi GPU driver needs. Plugs in via `providers.bootloader`, like
# finix's own Limine module.
#
# Requires `programs.limine.enable = false;` (that module claims the
# "limine" backend and brings in the Python installer).
{
  config,
  pkgs,
  lib,
  ...
}: let
  esp = config.boot.loader.efi.efiSysMountPoint;
  keep = 5; # generations shown in the menu
  timeout = 5; # seconds
  limine = pkgs.limine;

  installScript = pkgs.writeScript "install-limine" ''
    #!${pkgs.busybox}/bin/ash
    set -e
    export PATH=${
      lib.makeBinPath [
        pkgs.busybox
        pkgs.jq
      ]
    }
    esp=${esp}
    mountpoint -q "$esp" || { echo "limine: $esp is not mounted, aborting" >&2; exit 1; }
    keep=${toString keep}
    profiles=/nix/var/nix/profiles
    kdir=$esp/limine/kernels

    mkdir -p $kdir $esp/EFI/BOOT $esp/m1n1

    # Write via temp file + rename; FAT handles interrupted writes poorly.
    copy() {
      cp "$1" "$2.tmp"
      mv "$2.tmp" "$2"
    }

    # m1n1 stage 2 + DTBs + U-Boot (previously via programs.limine.additionalFiles)
    copy ${config.system.build.m1n1} $esp/m1n1/boot.bin

    # Limine itself, at the removable path U-Boot loads.
    copy ${limine}/share/limine/BOOTAA64.EFI $esp/EFI/BOOT/BOOTAA64.EFI

    # Copy a store file into limine/kernels once. Same naming as finix's
    # installer (<store-dir-name>-<file-name>), so existing files are reused.
    : > $kdir/.keep
    put() {
      name=$(basename "$(dirname "$1")")-$(basename "$1")
      [ -f "$kdir/$name" ] || copy "$1" "$kdir/$name"
      echo "$name" >> $kdir/.keep
      echo "boot():/limine/kernels/$name"
    }

    # Read a field from a generation's bootspec (boot.json).
    spec() {
      jq -r --arg k "$2" '."org.nixos.bootspec.v1"[$k]' "$1/boot.json"
    }

    entry() { # generation-path number
      k=$(put "$(spec "$1" kernel)")
      i=$(put "$(spec "$1" initrd)")
      init=$(spec "$1" init)
      label=$(spec "$1" label)
      params=$(jq -r '."org.nixos.bootspec.v1".kernelParams | join(" ")' "$1/boot.json")
      printf '/Generation %s\nprotocol: linux\ncomment: %s\nkernel_path: %s\ncmdline: init=%s %s\nmodule_path: %s\n\n' \
        "$2" "$label" "$k" "$init" "$params" "$i"
    }

    gens=$(ls -d $profiles/system-*-link \
      | sed 's|.*/system-\([0-9]*\)-link|\1|' \
      | sort -rn | head -n $keep)
    newest=$(echo "$gens" | head -n 1)

    # First entry (newest generation) is Limine's default.
    conf=$esp/limine/limine.conf
    {
      echo "timeout: ${toString timeout}"
      echo "editor_enabled: yes"
      echo "graphics: yes"
      echo "backdrop: 2F302F"
      echo
      for n in $gens; do
        entry "$profiles/system-$n-link" "$n"
      done
    } > $conf.tmp
    mv $conf.tmp $conf

    # Remove kernels/initrds no longer referenced. Only touches limine/kernels.
    for f in $kdir/*; do
      [ -f "$f" ] || continue
      grep -qxF "$(basename "$f")" $kdir/.keep || rm -f "$f"
    done

    sync
    echo "limine: wrote $conf (default: generation $newest)"
  '';

  # Same script on PATH, so it can be run by hand for testing.
  installBin = pkgs.runCommand "install-limine-bin" {} ''
    mkdir -p $out/bin
    ln -s ${installScript} $out/bin/install-limine
  '';
in {
  # finix's backend option is an enum; enum declarations merge across modules.
  options.providers.bootloader.backend = lib.mkOption {
    type = lib.types.enum ["limine-sh"];
  };

  config = lib.mkMerge [
    {environment.systemPackages = [installBin];}

    (lib.mkIf (config.providers.bootloader.backend == "limine-sh") {
      providers.bootloader.installHook = installScript;
    })
  ];
}
