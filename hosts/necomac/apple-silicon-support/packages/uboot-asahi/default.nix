{
  lib,
  fetchFromGitHub,
  buildUBoot,
  m1n1,
}:

(buildUBoot rec {
  src = fetchFromGitHub {
    owner = "AsahiLinux";
    repo = "u-boot";
    tag = "asahi-v2026.07-3";
    hash = "sha256-DbXS8L3j5w8ryYknR+DnAonAdPMNNLaBwWyc27vK0r4=";
  };
  version = "2026.07-3-asahi";

  defconfig = "apple_m1_defconfig";
  extraMeta.platforms = [ "aarch64-linux" ];
  filesToInstall = [
    "u-boot-nodtb.bin.gz"
    "m1n1-u-boot.bin"
  ];
  extraConfig = ''
    CONFIG_IDENT_STRING=" ${version}"
    CONFIG_VIDEO_FONT_4X6=n
    CONFIG_VIDEO_FONT_8X16=n
    CONFIG_VIDEO_FONT_SUN12X22=n
    CONFIG_VIDEO_FONT_16X32=y
    CONFIG_CMD_BOOTMENU=y

    CONFIG_VIDEO_LOGO=n
    CONFIG_DISPLAY_BOARDINFO_LATE=n
    CONFIG_SYS_CONSOLE_INFO_QUIET=y

    CONFIG_CMD_SELECT_FONT=n
    CONFIG_CMD_SMBIOS=n

    CONFIG_BOOTDELAY=0
    CONFIG_USE_PREBOOT=n

    CONFIG_BOOTCOMMAND="if load nvme ''${fw_dev_part} ''${kernel_addr_r} /EFI/BOOT/BOOTAA64.EFI; then bootefi ''${kernel_addr_r}; fi; bootflow scan -b"
  '';
}).overrideAttrs
  (o: {
    # nixos's downstream patches are not applicable
    patches = [
    ];

    preInstall = ''
      # compress so that m1n1 knows U-Boot's size and can find things after it
      gzip -n u-boot-nodtb.bin
      cat ${m1n1}/lib/m1n1/m1n1.bin arch/arm/dts/t[68]*.dtb u-boot-nodtb.bin.gz > m1n1-u-boot.bin
    '';

    postPatch = (o.postPatch or "") + ''
      substituteInPlace board/apple/mac/mac.env \
        --replace-fail 'stdout=vidconsole,serial' 'stdout=vidconsole' \
        --replace-fail 'stderr=vidconsole,serial' 'stderr=vidconsole'
    '';
  })
