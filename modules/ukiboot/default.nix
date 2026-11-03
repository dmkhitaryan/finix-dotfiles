{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.programs.ukiboot;
  aarchInfo =
    {
      x86_64-linux = {
        bootFileName = "BOOTX64.EFI";
        efiArch = "x64";
      };
      aarch64-linux = {
        bootFileName = "BOOTAA64.EFI";
        efiArch = "aa64";
      };
      riscv64-linux = {
        bootFileName = "BOOTRISCV64.EFI";
        efiArch = "riscv64";
      };
    }.${
      pkgs.stdenv.hostPlatform.system
    } or (throw "programs.ukiboot: Unsupported system ${pkgs.stdenv.hostPlatform.system}");
  ukiHook = pkgs.writeScript "ukiboot-install" ''
    #!${lib.getExe config.programs.sh.package}
    set -eu
    # Helpers
    readonly cursys="$1"
    currentRev=$(
      for link in /nix/var/nix/profiles/system-*-link; do
        if [ "$link" -ef "$cursys" ]; then
          n=''${link%-link}
          printf '%s\n' "''${n##*-}"
          break
        fi
      done
    )
    cutOff=$((currentRev - ${lib.toString cfg.maxGenerations}))
    lastRev=$((currentRev - 1))
    vendorName=$(. ${config.environment.etc."os-release".source} && printf '%s\n' "''${VENDOR_NAME:-''${NAME:-NixOS}}")
    backupName=$(printf '%s\n' "''${vendorName}_''$lastRev.EFI")
    bootName="${cfg.bootName}"
    kernelPath="${config.boot.kernelPackages.kernel}/${config.boot.kernelPackages.kernel.target or config.boot.kernelPackages.stdenv.hostPlatform.linux-kernel.target}"
    # First-time assurance
    ${lib.getExe' config.programs.coreutils.package "mkdir"} -p "${cfg.bootDir}"
    ${lib.getExe' config.programs.coreutils.package "mkdir"} -p "${cfg.backupDir}"
    # Installation
    ${lib.getExe' config.programs.coreutils.package "mv"} "${cfg.bootDir}/$bootName" "${cfg.backupDir}/$backupName"
    if [ "${lib.boolToString cfg.secureBoot.enable}" = "true" ]; then
      if [ -d "${cfg.secureBoot.keyLocation}" ]; then
        ${cfg.secureBoot.command} ${cfg.commandOptions.extraArrgs} || {
          echo "Ukiboot: UKI generation or signing failed, aborting." >&2
          exit 105
        }
      else
        echo "Ukiboot: Key directory, '${cfg.secureBoot.keyLocation}' doesn't exist" >&2
        exit 105
      fi
    else      
      ${lib.getExe cfg.packages.ukiboot} build ${cfg.commandOptions.extraArrgs} || {
          echo "Ukiboot: UKI generation failed, aborting." >&2
          exit 106
        }
    fi
    # Cleanup
    for file in "${cfg.backupDir}"/"$vendorName"_*.EFI; do
      [ -f "$file" ] || continue
      filename=''${file##*/}
      number=''${filename#''${vendorName}_}
      number=''${number%.EFI}
      printf 'cleanup file=<%s> number=<%s> cutoff=<%s>\n' \
        "$file" "$number" "$cutOff" >&2
      if [ "$number" -le "''${cutOff}" ]; then
        ${lib.getExe' config.programs.coreutils.package "rm"} "$file"
      fi
    done
  '';
in {
  meta.maintainers = [
    lib.maintainers.Z4il
  ];
  options.programs.ukiboot = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to use an automatic UKI generator.
      '';
    };
    packages = {
      ukiboot = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ./graft-kernel/default.nix {
          coreutils = pkgs.coreutils.overrideAttrs (old: {
            doCheck = false;
          });
        };
        description = ''
          The package to use for ukiboot.
        '';
      };
      stub = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ./stem/default.nix {};
        description = ''
          The package to use for the UKI efi stub.
        '';
      };
      signTool = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ./pesign/default.nix {};
        description = ''
          The package to use when signing a UKI.
        '';
      };
    };
    maxGenerations = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        Number of generations (positive and >0) to keep in the backup folder.
      '';
    };
    commandOptions.extraArrgs = lib.mkOption {
      type = lib.types.str;
      default = "--os-release \"@${config.environment.etc."os-release".source}\" --output \"${cfg.bootDir}/$bootName\" --stub \"${cfg.packages.stub}/lib/stem/stem${cfg.efiArch}.efi\" --linux \"$kernelPath\" --initrd \"${config.boot.initrd.package}/initrd\" --cmdline \"${lib.concatStringsSep " " config.boot.kernelParams} init=$cursys/init\" --efi-arch \"${cfg.efiArch}\"";
      description = ''
        The arguments to pass to the ukiboot package.
      '';
    };
    secureBoot = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable secure boot, by default it uses [pesign](${pkgs.pesign.meta.homepage}). ${pkgs.pesign.meta.description}.
        '';
      };
      keyLocation = lib.mkOption {
        type = lib.types.str;
        default = "/etc/pki/pesign";
        description = ''
          Location of the keys used for secureboot signing, bring your own.
        '';
      };
      signTool = lib.mkOption {
        type = lib.types.enum [
          "sbsign"
          "pesign"
        ];
        default = "pesign";
        description = ''
          The backend to use for signing UKI entries, none are compatible with sbctl so you will have to either port the keys or remake them.
        '';
      };
      command = lib.mkOption {
        type = lib.types.str;
        default = "${lib.getExe cfg.packages.ukiboot} build --signtool \"${cfg.secureBoot.signTool}\" --secureboot-certificate-name \"${cfg.secureBoot.commandOptions.certificateName}\" --secureboot-certificate-dir \"${cfg.secureBoot.commandOptions.certificateDir}\" --secureboot-private-key \"${cfg.secureBoot.commandOptions.privateKey}\" --secureboot-certificate \"${cfg.secureBoot.commandOptions.certificate}\" --tools \"${cfg.packages.signTool}/bin\"";
        description = ''
          The command used to sign the UKI
        '';
      };
      commandOptions = {
        certificateName = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            The DB name to which `--secureboot-certificate-name` points.
          '';
        };
        certificateDir = lib.mkOption {
          type = lib.types.str;
          default = cfg.secureBoot.keyLocation;
          description = ''
            The DB path to which `--secureboot-certificate-dir` points.
          '';
        };
        privateKey = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            The DB path to which `--secureboot-private-key` points.
          '';
        };
        certificate = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            The DB path to which `--secureboot-certificate` points.
          '';
        };
      };
    };
    efiMountPoint = lib.mkOption {
      type = lib.types.str;
      default = config.boot.loader.efi.efiSysMountPoint;
      description = ''
        Where the EFI System Partition is mounted.
      '';
    };
    bootDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.efiMountPoint}/EFI/BOOT";
      description = ''
        Where to save the UKI.
      '';
    };
    backupDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.efiMountPoint}/EFI/$vendorName";
      description = ''
        Where to save UKI backups.
      '';
    };
    bootName = lib.mkOption {
      type = lib.types.str;
      default = aarchInfo.bootFileName;
      description = ''
        The default file name for the auto-detected file stored in bootDir
      '';
    };
    efiArch = lib.mkOption {
      type = lib.types.str;
      default = aarchInfo.efiArch;
      description = ''
        Value to pass to --efi-arch
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.packages.ukiboot
      cfg.packages.stub
    ];
    boot.loader.script = {
      enable = true;
      installHook = ukiHook;
    };
  };
}
