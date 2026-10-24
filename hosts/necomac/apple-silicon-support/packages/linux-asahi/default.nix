{
  lib,
  callPackage,
  linuxPackagesFor,
  _kernelPatches ? [],
  stdenv,
  overrideCC,
  llvmPackages,
} @ args: let
  clangStdenv = overrideCC stdenv (stdenv.cc.override (_: {extraBuildCommands = "";}));
  extraArgs =
    lib.removeAttrs args [
      "lib"
      "callPackage"
      "linuxPackagesFor"
      "_kernelPatches"
      "overrideCC"
      "llvmPackages"
    ]
    // {stdenv = clangStdenv;};

  linux-asahi-pkg = {
    lib,
    fetchFromGitHub,
    buildLinux,
    ...
  }:
    buildLinux (
      lib.recursiveUpdate rec {
        inherit lib;

        pname = "linux-asahi";
        version = "7.2.12";
        modDirVersion = version;
        extraMeta.branch = "7.0";

        src = fetchFromGitHub {
          owner = "AsahiLinux";
          repo = "linux";
          tag = "asahi-${version}-2";
          hash = "sha256-SswEGjPYVsROWsn/g4Vnz1Q2arZCfCyo8mlRR8MSYj8=";
        };

        ignoreConfigErrors = false;
        # Only build what defconfig, common-config and the options below enable.
        autoModules = false;
        defconfig = "defconfig necomac.config";
        extraMakeFlags = ["LLVM_LINK=${llvmPackages.llvm}/bin/llvm-link"];

        kernelPatches =
          [
            {
              name = "Asahi config";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                # Needed for GPU
                ARM64_16K_PAGES = yes;

                ARM64_MEMORY_MODEL_CONTROL = yes;
                ARM64_ACTLR_STATE = yes;

                # Might lead to the machine rebooting if not loaded soon enough
                APPLE_WATCHDOG = yes;

                # Can not be built as a module, defaults to no
                APPLE_M1_CPU_PMU = yes;

                # Defaults to 'y', but we want to allow the user to set options in modprobe.d
                HID_APPLE = module;

                APPLE_AOP = yes;
                APPLE_PMGR_MISC = yes;
                APPLE_PMGR_PWRSTATE = yes;
                DRM_ASAHI = yes;

                # Apple SoC drivers, set explicitly so they survive autoModules = false.
                APPLE_DART = yes;
                APPLE_SART = yes;
                APPLE_SIO = module;
                APPLE_ADMAC = module;
                ARM_APPLE_SOC_CPUFREQ = module;
                COMMON_CLK_APPLE_NCO = module;
                NVMEM_APPLE_SPMI = module;
                SPMI = yes;
                SPMI_APPLE = module;
                PINCTRL_APPLE_GPIO = module;
                PWM_APPLE = module;
                SPI_APPLE = module;
                I2C_APPLE = module;
                PCIE_APPLE = module;
                PHY_APPLE_ATC = module;
                NVME_APPLE = yes;
                DRM_APPLE = module;
                # Display crossbar lives behind the generic mux menu.
                MUX_CORE = yes;
                MUX_APPLE_DPXBAR = module;

                # System Management Controller.
                MFD_MACSMC = module;
                GPIO_MACSMC = module;
                SENSORS_MACSMC_HWMON = module;
                INPUT_MACSMC_INPUT = module;
                MACSMC_POWER = module;
                POWER_RESET_MACSMC = module;
                RTC_DRV_MACSMC = module;

                # Ambient light and lid angle sensors (via APPLE_AOP).
                IIO = yes;
                IIO_AOP_SENSOR_ALS = module;
                IIO_AOP_SENSOR_LAS = module;

                # Internal keyboard and trackpad.
                SPI_HID_APPLE_OF = module;
                HID_MAGICMOUSE = module;

                # USB-C and USB4/Thunderbolt.
                TYPEC = module;
                TYPEC_TPS6598X = module;
                USB4 = module;

                # SD card reader.
                MMC = yes;
                MMC_SDHCI = yes;
                MMC_SDHCI_PCI = module;
                MMC_SDHCI_UHS2 = module;

                # Wi-Fi and Bluetooth.
                RFKILL = module;
                CFG80211 = module;
                BRCMFMAC = module;
                BRCMFMAC_PCIE = yes;
                BT = module;
                BT_BREDR = yes;
                BT_RFCOMM = module;
                BT_BNEP = module;
                BT_HCIBCM4377 = module;

                # iwd needs AF_ALG and these algorithms.
                CRYPTO_USER_API_HASH = module;
                CRYPTO_USER_API_SKCIPHER = module;
                CRYPTO_USER_API_AEAD = module;
                CRYPTO_MD4 = module;
                CRYPTO_MD5 = module;
                CRYPTO_DES = module;
                CRYPTO_ECDH = module;
                #CRYPTO_SHA3 = module;
                #CRYPTO_SHA512 = module;

                # FUSE and VFAT codepages.
                FUSE_FS = module;
                NLS_CODEPAGE_437 = module;
                NLS_ISO8859_1 = module;

                # Root and ESP filesystems, plus exFAT sticks.
                EXT4_FS = yes;
                VFAT_FS = yes;
                EXFAT_FS = module;

                # Remaining initrd modules from configuration.nix.
                APPLE_RTKIT_HELPER = yes;
                APPLE_DOCKCHANNEL = yes;
                HID_DOCKCHANNEL = yes;
                NVMEM_APPLE_EFUSES = yes;
                USB_XHCI_HCD = yes;
                USB_XHCI_PLATFORM = yes;
                USB_DWC3 = yes;
                USB_DWC3_OF_SIMPLE = yes;
                USB_HID = yes;
                HID_GENERIC = yes;

                # USB mass storage.
                USB_STORAGE = yes;
                USB_UAS = module;

                # USB Ethernet dongles (CDC, Realtek, ASIX).
                USB_NET_DRIVERS = yes;
                USB_USBNET = module;
                USB_NET_CDCETHER = module;
                USB_NET_CDC_NCM = module;
                USB_RTL8152 = module;
                USB_NET_AX88179_178A = module;

                NVME_HOST_AUTH = lib.mkForce no;

                # Disable irrelevant entries.
                DRM_AMDGPU = no;
                DRM_NOUVEAU = no;
                DRM_RADEON = no;

                WLAN_VENDOR_ATH = no;
                WLAN_VENDOR_INTEL = no;
                WLAN_VENDOR_MEDIATEK = no;
                WLAN_VENDOR_ADMTEK = no;
                WLAN_VENDOR_ATMEL = no;
                # Keep WLAN_VENDOR_BROADCOM.
                WLAN_VENDOR_BROADCOM = yes;
                WLAN_VENDOR_INTERSIL = no;
                WLAN_VENDOR_MARVELL = no;
                WLAN_VENDOR_MICROCHIP = no;
                WLAN_VENDOR_PURELIFI = no;
                WLAN_VENDOR_RALINK = no;
                WLAN_VENDOR_REALTEK = no;
                WLAN_VENDOR_RSI = no;
                WLAN_VENDOR_SILABS = no;
                WLAN_VENDOR_ST = no;
                WLAN_VENDOR_TI = no;
                WLAN_VENDOR_ZYDAS = no;
                WLAN_VENDOR_QUANTENNA = no;

                NET_VENDOR_AMD = no;
                NET_VENDOR_INTEL = no;
                NET_VENDOR_NVIDIA = no;

                # Networking hardware/features not present on the J314.
                NET_DSA = no;
                WWAN = no;
                INFINIBAND = lib.mkForce no;

                # Unused virtualization.
                XEN = lib.mkForce no;
                HYPERV = lib.mkForce no;

                # Virtual/test GPUs.
                DRM_VGEM = no;
                DRM_VKMS = no;
                DRM_VIRTIO_GPU = no;

                # Less "consequence-free" clear.
                DEBUG_MEMORY_INIT = no;

                # Wrong Broadcom Wi-Fi implementations.

                # Completely irrelevant buses/features.
                WAN = lib.mkForce no;
                SPEAKUP = no;

                # Ancient Apple USB touchpads, not the J314 trackpad.
                MOUSE_APPLETOUCH = no;

                # Legacy framebuffer hardware.
                FB_NVIDIA = no;
                FB_RIVA = no;
                FB_I740 = no;
                FB_RADEON = no;
                FB_ATY128 = no;
                FB_ATY = no;
                FB_SAVAGE = no;
                FB_SIS = no;
                FB_NEOMAGIC = no;
                FB_KYRO = no;
                FB_3DFX = no;
                FB_VOODOO1 = no;
                FB_TRIDENT = no;
                FB_PM2 = no;
                FB_PM3 = no;
                FB_CIRRUS = no;
                FB_CYBER2000 = no;
                FB_UVESA = no;
                FB_OPENCORES = no;
                FB_TFT = no;

                ARCH_SUNXI = no;
                ARCH_BCM = no;
                ARCH_HISI = no;
                ARCH_MEDIATEK = no;
                ARCH_NXP = no;
                ARCH_QCOM = no;
                ARCH_TEGRA = no;

                RDS = no;
                TIPC = no;
                ATM = no;
                PHONET = no;
                IEEE802154 = no;
                #QRTR = no;
                CAN = no;
                NFC = no;
                #WWAN = no;

                # Unused filesystems.
                XFS_FS = no;
                OCFS2_FS = no;
                BTRFS_FS = no;
                F2FS_FS = lib.mkForce no;
                CEPH_FS = no;

                APPLE_MAILBOX = yes;
                APPLE_RTKIT = yes;
                RUST_APPLE_RTKIT = yes;

                ATA = no;
                SCSI_LOWLEVEL = lib.mkForce no;
                SCSI = yes;
                NVME_TARGET = lib.mkForce no;
                MAC80211 = no;

                NVME_FC = no;
                NVME_TCP = no;

                # No built-in Ethernet controller.
                NET_VENDOR_3COM = no;
                NET_VENDOR_ADAPTEC = no;
                NET_VENDOR_AGERE = no;
                NET_VENDOR_ALACRITECH = no;
                NET_VENDOR_AMAZON = no;
                NET_VENDOR_AQUANTIA = no;
                NET_VENDOR_ARC = no;
                NET_VENDOR_ASIX = no;
                NET_VENDOR_ATHEROS = no;
                NET_VENDOR_BROADCOM = no;
                NET_VENDOR_CADENCE = no;
                NET_VENDOR_CAVIUM = no;
                NET_VENDOR_CHELSIO = no;
                NET_VENDOR_CISCO = no;
                NET_VENDOR_CORTINA = no;
                NET_VENDOR_DAVICOM = no;
                NET_VENDOR_DEC = no;
                NET_VENDOR_DLINK = no;
                NET_VENDOR_EMULEX = no;
                NET_VENDOR_ENGLEDER = no;
                NET_VENDOR_EZCHIP = no;
                NET_VENDOR_FUNGIBLE = no;
                NET_VENDOR_GOOGLE = no;
                NET_VENDOR_HISILICON = no;
                NET_VENDOR_HUAWEI = no;
                NET_VENDOR_ADI = no;
                NET_VENDOR_LITEX = no;
                NET_VENDOR_MARVELL = no;
                NET_VENDOR_MELLANOX = no;
                NET_VENDOR_META = no;
                NET_VENDOR_MICREL = no;
                NET_VENDOR_MICROCHIP = no;
                NET_VENDOR_MICROSEMI = no;
                NET_VENDOR_MICROSOFT = no;
                NET_VENDOR_MUCSE = no;
                NET_VENDOR_MYRI = no;
                NET_VENDOR_NI = no;
                NET_VENDOR_NATSEMI = no;
                NET_VENDOR_NETRONOME = no;
                NET_VENDOR_OKI = no;
                NET_VENDOR_PENSANDO = no;
                NET_VENDOR_QLOGIC = no;
                NET_VENDOR_BROCADE = no;
                NET_VENDOR_QUALCOMM = no;
                NET_VENDOR_RDC = no;
                NET_VENDOR_REALTEK = no;
                NET_VENDOR_RENESAS = no;
                NET_VENDOR_ROCKER = no;
                NET_VENDOR_SAMSUNG = no;
                NET_VENDOR_SEEQ = no;
                NET_VENDOR_SILAN = no;
                NET_VENDOR_SIS = no;
                NET_VENDOR_SOLARFLARE = no;
                NET_VENDOR_SMSC = no;
                NET_VENDOR_SOCIONEXT = no;
                NET_VENDOR_STMICRO = no;
                NET_VENDOR_SUN = no;
                NET_VENDOR_SYNOPSYS = no;
                NET_VENDOR_TEHUTI = no;
                NET_VENDOR_TI = no;
                NET_VENDOR_VERTEXCOM = no;
                NET_VENDOR_VIA = no;
                NET_VENDOR_WANGXUN = no;
                NET_VENDOR_WIZNET = no;
                NET_VENDOR_XILINX = no;

                # Media type toggles only take effect with the filter on;
                # stock sets EXPERT, which turns the filter off by default.
                MEDIA_SUPPORT = module;
                MEDIA_SUPPORT_FILTER = yes;

                # Camera (ISP) and video decoder (AVD).
                MEDIA_CAMERA_SUPPORT = yes;
                MEDIA_PLATFORM_SUPPORT = yes;
                MEDIA_CONTROLLER = yes;
                MEDIA_PLATFORM_DRIVERS = yes;
                V4L_PLATFORM_DRIVERS = yes;
                VIDEO_DEV = module;
                VIDEO_APPLE_ISP = module;
                VIDEO_APPLE_AVD = module;

                # No TV / DVB / radio / SDR hardware.
                MEDIA_ANALOG_TV_SUPPORT = lib.mkForce no;
                MEDIA_DIGITAL_TV_SUPPORT = lib.mkForce no;
                MEDIA_RADIO_SUPPORT = no;
                MEDIA_SDR_SUPPORT = no;
                MEDIA_TEST_SUPPORT = no;

                # No PCI capture/TV cards.
                MEDIA_PCI_SUPPORT = lib.mkForce no;

                # Sound core and USB audio.
                SOUND = module;
                SND = module;
                SND_SOC = module;
                SND_USB_AUDIO = module;

                SND_PCI = no;
                SND_DRIVERS = no;
                SND_OSSEMUL = lib.mkForce no;

                SND_SOC_USB = no;

                SND_SOC_ADI_AXI_I2S = no;
                SND_SOC_ADI_AXI_SPDIF = no;

                SND_SOC_AMD_ACP = no;

                SND_SOC_FSL_ASRC = no;
                SND_SOC_FSL_SAI = no;
                SND_SOC_FSL_AUDMIX = no;
                SND_SOC_FSL_SSI = no;
                SND_SOC_FSL_SPDIF = no;
                SND_SOC_FSL_ESAI = no;
                SND_SOC_FSL_MICFIL = no;
                SND_SOC_FSL_XCVR = no;
                SND_SOC_FSL_RPMSG = no;
                SND_SOC_IMX_AUDMUX = no;

                SND_SOC_MTK_BTCVSD = no;

                SND_SOC_XILINX_I2S = no;
                SND_SOC_XILINX_AUDIO_FORMATTER = no;
                SND_SOC_XILINX_SPDIF = no;
                SND_SOC_XTFPGA_I2S = no;

                SND_SOC_SOF_TOPLEVEL = no;

                SND_SOC_APPLE_AOP_AUDIO = module;
                SND_SOC_APPLE_MCA = module;
                SND_SOC_APPLE_MACAUDIO = module;
                SND_SOC_MIKROE_PROTO = no;
                SND_SOC_CHV3_I2S = no;
                SND_SOC_AC97_CODEC = no;
                SND_SOC_ADAU1372_I2C = no;
                SND_SOC_ADAU1372_SPI = no;
                SND_SOC_ADAU1373 = no;
                SND_SOC_ADAU1701 = no;
                SND_SOC_ADAU1761_I2C = no;
                SND_SOC_ADAU1761_SPI = no;
                SND_SOC_ADAU7002 = no;
                SND_SOC_ADAU7118_HW = no;
                SND_SOC_ADAU7118_I2C = no;
                SND_SOC_AK4104 = no;
                SND_SOC_AK4118 = no;
                SND_SOC_AK4375 = no;
                SND_SOC_AK4458 = no;
                SND_SOC_AK4554 = no;
                SND_SOC_AK4613 = no;
                SND_SOC_AK4619 = no;
                SND_SOC_AK4642 = no;
                SND_SOC_AK5386 = no;
                SND_SOC_AK5558 = no;
                SND_SOC_ALC5623 = no;
                SND_SOC_AUDIO_IIO_AUX = no;
                SND_SOC_AW8738 = no;
                SND_SOC_AW88395 = no;
                SND_SOC_AW88166 = no;
                SND_SOC_AW88261 = no;
                SND_SOC_AW88081 = no;
                SND_SOC_AW87390 = no;
                SND_SOC_AW88399 = no;
                SND_SOC_BD28623 = no;
                SND_SOC_BT_SCO = no;
                SND_SOC_CHV3_CODEC = no;
                SND_SOC_CS35L32 = no;
                SND_SOC_CS35L33 = no;
                SND_SOC_CS35L34 = no;
                SND_SOC_CS35L35 = no;
                SND_SOC_CS35L36 = no;
                SND_SOC_CS35L41_SPI = no;
                SND_SOC_CS35L41_I2C = no;
                SND_SOC_CS35L45_SPI = no;
                SND_SOC_CS35L45_I2C = no;
                SND_SOC_CS35L56_I2C = no;
                SND_SOC_CS35L56_SPI = no;
                SND_SOC_CS35L56_SDW = no;
                SND_SOC_CS42L42 = no;
                SND_SOC_CS42L42_SDW = no;
                SND_SOC_CS42L51_I2C = no;
                SND_SOC_CS42L52 = no;
                SND_SOC_CS42L56 = no;
                SND_SOC_CS42L73 = no;
                SND_SOC_CS4234 = no;
                SND_SOC_CS4265 = no;
                SND_SOC_CS4270 = no;
                SND_SOC_CS4271_I2C = no;
                SND_SOC_CS4271_SPI = no;
                SND_SOC_CS42XX8_I2C = no;
                SND_SOC_CS43130 = no;
                SND_SOC_CS4341 = no;
                SND_SOC_CS4349 = no;
                SND_SOC_CS48L32 = no;
                SND_SOC_CS53L30 = no;
                SND_SOC_CS530X_I2C = no;
                SND_SOC_CS530X_SPI = no;
                SND_SOC_CX2072X = no;
                SND_SOC_DA7213 = no;
                SND_SOC_DMIC = module;
                SND_SOC_ES7134 = no;
                SND_SOC_ES7241 = no;
                SND_SOC_ES8311 = no;
                SND_SOC_ES8316 = no;
                SND_SOC_ES8323 = no;
                SND_SOC_ES8326 = no;
                SND_SOC_ES8328_I2C = no;
                SND_SOC_ES8328_SPI = no;
                SND_SOC_ES8375 = no;
                SND_SOC_ES8389 = no;
                SND_SOC_FS210X = no;
                SND_SOC_GTM601 = no;
                SND_SOC_HDA = no;
                SND_SOC_ICS43432 = no;
                SND_SOC_IDT821034 = no;
                SND_SOC_MAX98088 = no;
                SND_SOC_MAX98090 = no;
                SND_SOC_MAX98357A = no;
                SND_SOC_MAX98504 = no;
                SND_SOC_MAX9867 = no;
                SND_SOC_MAX98927 = no;
                SND_SOC_MAX98520 = no;
                SND_SOC_MAX98363 = no;
                SND_SOC_MAX98373_I2C = no;
                SND_SOC_MAX98373_SDW = no;
                SND_SOC_MAX98388 = no;
                SND_SOC_MAX98390 = no;
                SND_SOC_MAX98396 = no;
                SND_SOC_MAX9860 = no;
                SND_SOC_MSM8916_WCD_ANALOG = no;
                SND_SOC_MSM8916_WCD_DIGITAL = no;
                SND_SOC_PCM1681 = no;
                SND_SOC_PCM1754 = no;
                SND_SOC_PCM1789_I2C = no;
                SND_SOC_PCM179X_I2C = no;
                SND_SOC_PCM179X_SPI = no;
                SND_SOC_PCM186X_I2C = no;
                SND_SOC_PCM186X_SPI = no;
                SND_SOC_PCM3060_I2C = no;
                SND_SOC_PCM3060_SPI = no;
                SND_SOC_PCM3168A_I2C = no;
                SND_SOC_PCM3168A_SPI = no;
                SND_SOC_PCM5102A = no;
                SND_SOC_PCM512x_I2C = no;
                SND_SOC_PCM512x_SPI = no;
                SND_SOC_PCM6240 = no;
                SND_SOC_PEB2466 = no;
                SND_SOC_PM4125_SDW = no;
                SND_SOC_RK817 = no;
                SND_SOC_RT1017_SDCA_SDW = no;
                SND_SOC_RT1308_SDW = no;
                SND_SOC_RT1316_SDW = no;
                SND_SOC_RT1318_SDW = no;
                SND_SOC_RT1320_SDW = no;
                SND_SOC_RT5575 = no;
                SND_SOC_RT5616 = no;
                SND_SOC_RT5631 = no;
                SND_SOC_RT5640 = no;
                SND_SOC_RT5659 = no;
                SND_SOC_RT5682_SDW = no;
                SND_SOC_RT700_SDW = no;
                SND_SOC_RT711_SDW = no;
                SND_SOC_RT711_SDCA_SDW = no;
                SND_SOC_RT712_SDCA_SDW = no;
                SND_SOC_RT712_SDCA_DMIC_SDW = no;
                SND_SOC_RT721_SDCA_SDW = no;
                SND_SOC_RT722_SDCA_SDW = no;
                SND_SOC_RT715_SDW = no;
                SND_SOC_RT715_SDCA_SDW = no;
                SND_SOC_RT9120 = no;
                SND_SOC_RT9123 = no;
                SND_SOC_RT9123P = no;
                SND_SOC_RTQ9124 = no;
                SND_SOC_RTQ9128 = no;
                SND_SOC_SDW_MOCKUP = no;
                SND_SOC_SGTL5000 = no;
                SND_SOC_SIMPLE_AMPLIFIER = no;
                SND_SOC_SIMPLE_MUX = no;
                SND_SOC_SMA1303 = no;
                SND_SOC_SMA1307 = no;
                SND_SOC_SPDIF = no;
                SND_SOC_SRC4XXX_I2C = no;
                SND_SOC_SSM2305 = no;
                SND_SOC_SSM2518 = no;
                SND_SOC_SSM2602_SPI = no;
                SND_SOC_SSM2602_I2C = no;
                SND_SOC_SSM3515 = no;
                SND_SOC_SSM4567 = no;
                SND_SOC_STA32X = no;
                SND_SOC_STA350 = no;
                SND_SOC_STI_SAS = no;
                SND_SOC_TAS2552 = no;
                SND_SOC_TAS2562 = no;
                SND_SOC_TAS2780 = no;
                SND_SOC_TAS2781_I2C = no;
                SND_SOC_TAS5086 = no;
                SND_SOC_TAS571X = no;
                SND_SOC_TAS5720 = no;
                SND_SOC_TAS5805M = no;
                SND_SOC_TAS6424 = no;
                SND_SOC_TDA7419 = no;
                SND_SOC_TFA9879 = no;
                SND_SOC_TFA989X = no;
                SND_SOC_TLV320ADC3XXX = no;
                SND_SOC_TLV320AIC23_I2C = no;
                SND_SOC_TLV320AIC23_SPI = no;
                SND_SOC_TLV320AIC31XX = no;
                SND_SOC_TLV320AIC32X4_I2C = no;
                SND_SOC_TLV320AIC32X4_SPI = no;
                SND_SOC_TLV320AIC3X_I2C = no;
                SND_SOC_TLV320AIC3X_SPI = no;
                SND_SOC_TLV320ADCX140 = no;
                SND_SOC_TS3A227E = no;
                SND_SOC_TSCS42XX = no;
                SND_SOC_TSCS454 = no;
                SND_SOC_UDA1334 = no;
                SND_SOC_UDA1342 = no;
                SND_SOC_UDA1380 = no;
                SND_SOC_WCD9335 = no;
                SND_SOC_WCD934X = no;
                SND_SOC_WCD937X_SDW = no;
                SND_SOC_WCD938X_SDW = no;
                SND_SOC_WCD939X_SDW = no;
                SND_SOC_WM8510 = no;
                SND_SOC_WM8523 = no;
                SND_SOC_WM8524 = no;
                SND_SOC_WM8580 = no;
                SND_SOC_WM8711 = no;
                SND_SOC_WM8728 = no;
                SND_SOC_WM8731_I2C = no;
                SND_SOC_WM8731_SPI = no;
                SND_SOC_WM8737 = no;
                SND_SOC_WM8741 = no;
                SND_SOC_WM8750 = no;
                SND_SOC_WM8753 = no;
                SND_SOC_WM8770 = no;
                SND_SOC_WM8776 = no;
                SND_SOC_WM8782 = no;
                SND_SOC_WM8804_I2C = no;
                SND_SOC_WM8804_SPI = no;
                SND_SOC_WM8903 = no;
                SND_SOC_WM8904 = no;
                SND_SOC_WM8940 = no;
                SND_SOC_WM8960 = no;
                SND_SOC_WM8961 = no;
                SND_SOC_WM8962 = no;
                SND_SOC_WM8974 = no;
                SND_SOC_WM8978 = no;
                SND_SOC_WM8985 = no;
                SND_SOC_WSA881X = no;
                SND_SOC_WSA883X = no;
                SND_SOC_WSA884X = no;
                SND_SOC_ZL38060 = no;
                SND_SOC_MAX9759 = no;
                SND_SOC_MT6351 = no;
                SND_SOC_MT6357 = no;
                SND_SOC_MT6358 = no;
                SND_SOC_MT6660 = no;
                SND_SOC_NAU8315 = no;
                SND_SOC_NAU8325 = no;
                SND_SOC_NAU8540 = no;
                SND_SOC_NAU8810 = no;
                SND_SOC_NAU8821 = no;
                SND_SOC_NAU8822 = no;
                SND_SOC_NAU8824 = no;
                SND_SOC_NTP8918 = no;
                SND_SOC_NTP8835 = no;
                SND_SOC_TPA6130A2 = no;
                SND_SOC_LPASS_WSA_MACRO = no;
                SND_SOC_LPASS_VA_MACRO = no;
                SND_SOC_LPASS_RX_MACRO = no;
                SND_SOC_LPASS_TX_MACRO = no;

                # Only platform this kernel targets.
                ARCH_APPLE = yes;

                ARCH_ACTIONS = no;
                ARCH_AIROHA = no;
                ARCH_ALPINE = no;
                ARCH_BERLIN = no;
                ARCH_BLAIZE = no;
                ARCH_BST = no;
                ARCH_CIX = no;
                ARCH_EXYNOS = no;
                ARCH_K3 = no;
                ARCH_LG1K = no;
                ARCH_KEEMBAY = no;
                ARCH_MESON = no;
                ARCH_MICROCHIP = no;
                ARCH_MVEBU = no;
                ARCH_MA35 = no;
                ARCH_NPCM = no;
                ARCH_REALTEK = no;
                ARCH_RENESAS = no;
                ARCH_ROCKCHIP = no;
                ARCH_SEATTLE = no;
                ARCH_INTEL_SOCFPGA = no;
                ARCH_SOPHGO = no;
                ARCH_STM32 = no;
                ARCH_SYNQUACER = no;
                ARCH_SPRD = no;
                ARCH_THUNDER = no;
                ARCH_THUNDER2 = no;
                ARCH_UNIPHIER = no;
                ARCH_VEXPRESS = no;
                ARCH_VISCONTI = no;
                ARCH_XGENE = no;
                ARCH_ZYNQMP = no;
                CP15_BARRIER_EMULATION = lib.mkForce (option no);
                DEFAULT_SECURITY_APPARMOR = lib.mkForce (option no);
                MEM_ALLOC_PROFILING_ENABLED_BY_DEFAULT = lib.mkForce (option no);
                NET_VENDOR_MEDIATEK = lib.mkForce (option no);
                SCHED_CLASS_EXT = lib.mkForce (option no);
                # Orphaned by disabled parents; common-config still requests them.
                "8139TOO_8129" = lib.mkForce (option no);
                "8139TOO_PIO" = lib.mkForce (option no);
                AIC79XX_DEBUG_ENABLE = lib.mkForce (option no);
                AIC7XXX_DEBUG_ENABLE = lib.mkForce (option no);
                AIC94XX_DEBUG = lib.mkForce (option no);
                ATA_BMDMA = lib.mkForce (option no);
                ATA_SFF = lib.mkForce (option no);
                BFQ_GROUP_IOSCHED = lib.mkForce (option no);
                BPF_EVENTS = lib.mkForce (option no);
                BTRFS_FS_POSIX_ACL = lib.mkForce (option no);
                BT_HCIBTUSB_AUTOSUSPEND = lib.mkForce (option no);
                BT_HCIBTUSB_MTK = lib.mkForce (option no);
                BT_HCIUART_QCA = lib.mkForce (option no);
                BT_HCIUART_SERDEV = lib.mkForce (option no);
                BT_QCA = lib.mkForce (option no);
                CEPH_FSCACHE = lib.mkForce (option no);
                CEPH_FS_POSIX_ACL = lib.mkForce (option no);
                CHROMEOS_TBMC = lib.mkForce (option no);
                CIFS_DFS_UPCALL = lib.mkForce (option no);
                CIFS_FSCACHE = lib.mkForce (option no);
                CIFS_UPCALL = lib.mkForce (option no);
                CIFS_XATTR = lib.mkForce (option no);
                CLS_U32_MARK = lib.mkForce (option no);
                CLS_U32_PERF = lib.mkForce (option no);
                CROS_EC = lib.mkForce (option no);
                CROS_EC_I2C = lib.mkForce (option no);
                CROS_EC_SPI = lib.mkForce (option no);
                CROS_KBD_LED_BACKLIGHT = lib.mkForce (option no);
                CRYPTO_AEGIS128_SIMD = lib.mkForce (option no);
                CRYPTO_DRBG_CTR = lib.mkForce (option no);
                CRYPTO_DRBG_HASH = lib.mkForce (option no);
                DRAGONRISE_FF = lib.mkForce (option no);
                DRM_AMDGPU_CIK = lib.mkForce (option no);
                DRM_AMDGPU_SI = lib.mkForce (option no);
                DRM_AMDGPU_USERPTR = lib.mkForce (option no);
                DRM_AMD_ACP = lib.mkForce (option no);
                DRM_AMD_DC_SI = lib.mkForce (option no);
                DRM_AMD_ISP = lib.mkForce (option no);
                DRM_HYPERV = lib.mkForce (option no);
                DRM_NOUVEAU_SVM = lib.mkForce (option no);
                DRM_VC4_HDMI_CEC = lib.mkForce (option no);
                EROFS_FS_ZIP_DEFLATE = lib.mkForce (option no);
                EROFS_FS_ZIP_ZSTD = lib.mkForce (option no);
                EXT2_FS_POSIX_ACL = lib.mkForce (option no);
                EXT2_FS_SECURITY = lib.mkForce (option no);
                EXT2_FS_XATTR = lib.mkForce (option no);
                F2FS_FS_COMPRESSION = lib.mkForce (option no);
                FB_3DFX_ACCEL = lib.mkForce (option no);
                FB_ATY_CT = lib.mkForce (option no);
                FB_ATY_GX = lib.mkForce (option no);
                FB_NVIDIA_I2C = lib.mkForce (option no);
                FB_RIVA_I2C = lib.mkForce (option no);
                FB_SAVAGE_ACCEL = lib.mkForce (option no);
                FB_SAVAGE_I2C = lib.mkForce (option no);
                FB_SIS_300 = lib.mkForce (option no);
                FB_SIS_315 = lib.mkForce (option no);
                FSCACHE_STATS = lib.mkForce (option no);
                FSL_MC_UAPI_SUPPORT = lib.mkForce (option no);
                FTRACE_SYSCALLS = lib.mkForce (option no);
                FUNCTION_GRAPH_RETVAL = lib.mkForce (option no);
                FUNCTION_PROFILER = lib.mkForce (option no);
                FUNCTION_TRACER = lib.mkForce (option no);
                GREENASIA_FF = lib.mkForce (option no);
                HID_ACRUX_FF = lib.mkForce (option no);
                HID_BPF = lib.mkForce (option no);
                HMM_MIRROR = lib.mkForce (option no);
                HOLTEK_FF = lib.mkForce (option no);
                HSA_AMD = lib.mkForce (option no);
                HSA_AMD_P2P = lib.mkForce (option no);
                INET6_ESPINTCP = lib.mkForce (option no);
                INET_ESPINTCP = lib.mkForce (option no);
                INET_MPTCP_DIAG = lib.mkForce (option no);
                INFINIBAND_IPOIB = lib.mkForce (option no);
                INFINIBAND_IPOIB_CM = lib.mkForce (option no);
                IPE_PROP_FS_VERITY = lib.mkForce (option no);
                IPE_PROP_FS_VERITY_BUILTIN_SIG = lib.mkForce (option no);
                JOYSTICK_PSXPAD_SPI_FF = lib.mkForce (option no);
                L2TP_ETH = lib.mkForce (option no);
                L2TP_IP = lib.mkForce (option no);
                L2TP_V3 = lib.mkForce (option no);
                LOGIG940_FF = lib.mkForce (option no);
                LOGIRUMBLEPAD2_FF = lib.mkForce (option no);
                LOGITECH_FF = lib.mkForce (option no);
                LOGIWHEELS_FF = lib.mkForce (option no);
                MAC80211_DEBUGFS = lib.mkForce (option no);
                MEDIA_ATTACH = lib.mkForce (option no);
                MEGARAID_NEWGEN = lib.mkForce (option no);
                MPTCP_IPV6 = lib.mkForce (option no);
                MT798X_WMAC = lib.mkForce (option no);
                NETFILTER_NETLINK_GLUE_CT = lib.mkForce (option no);
                NET_DROP_MONITOR = lib.mkForce (option no);
                NET_SCH_BPF = lib.mkForce (option no);
                NFSD_V3_ACL = lib.mkForce (option no);
                NFSD_V4 = lib.mkForce (option no);
                NFSD_V4_SECURITY_LABEL = lib.mkForce (option no);
                NFS_FSCACHE = lib.mkForce (option no);
                NFS_LOCALIO = lib.mkForce (option no);
                NFS_SWAP = lib.mkForce (option no);
                NFS_V3_ACL = lib.mkForce (option no);
                NFS_V4_2 = lib.mkForce (option no);
                NFS_V4_SECURITY_LABEL = lib.mkForce (option no);
                NFT_REJECT_NETDEV = lib.mkForce (option no);
                NF_FLOW_TABLE_PROCFS = lib.mkForce (option no);
                NF_TABLES_ARP = lib.mkForce (option no);
                NF_TABLES_BRIDGE = lib.mkForce (option no);
                NF_TABLES_INET = lib.mkForce (option no);
                NF_TABLES_IPV4 = lib.mkForce (option no);
                NF_TABLES_IPV6 = lib.mkForce (option no);
                NF_TABLES_NETDEV = lib.mkForce (option no);
                NINTENDO_FF = lib.mkForce (option no);
                NTFS3_FS_POSIX_ACL = lib.mkForce (option no);
                NTFS3_LZX_XPRESS = lib.mkForce (option no);
                NTFS_FS_POSIX_ACL = lib.mkForce (option no);
                NVIDIA_SHIELD_FF = lib.mkForce (option no);
                NVME_AUTH = lib.mkForce (option no);
                NVME_TARGET_AUTH = lib.mkForce (option no);
                NVME_TARGET_PASSTHRU = lib.mkForce (option no);
                NVME_TARGET_TCP_TLS = lib.mkForce (option no);
                NVME_TCP_TLS = lib.mkForce (option no);
                PLAYSTATION_FF = lib.mkForce (option no);
                PPP_FILTER = lib.mkForce (option no);
                PPP_MULTILINK = lib.mkForce (option no);
                RING_BUFFER_BENCHMARK = lib.mkForce (option no);
                ROCKCHIP_DW_HDMI_QP = lib.mkForce (option no);
                ROCKCHIP_DW_MIPI_DSI2 = lib.mkForce (option no);
                RT2800USB_RT53XX = lib.mkForce (option no);
                RT2800USB_RT55XX = lib.mkForce (option no);
                RTW88 = lib.mkForce (option no);
                RTW88_8822BE = lib.mkForce (option no);
                RTW88_8822CE = lib.mkForce (option no);
                SATA_MOBILE_LPM_POLICY = lib.mkForce (option no);
                SCHED_TRACER = lib.mkForce (option no);
                SCSI_LOWLEVEL_PCMCIA = lib.mkForce (option no);
                SCSI_SAS_ATA = lib.mkForce (option no);
                SLIP_COMPRESSED = lib.mkForce (option no);
                SLIP_SMART = lib.mkForce (option no);
                SMARTJOYPLUS_FF = lib.mkForce (option no);
                SND_AC97_POWER_SAVE = lib.mkForce (option no);
                SND_AC97_POWER_SAVE_DEFAULT = lib.mkForce (option no);
                SND_HDA_CODEC_CS8409 = lib.mkForce (option no);
                SND_HDA_INPUT_BEEP = lib.mkForce (option no);
                SND_HDA_PATCH_LOADER = lib.mkForce (option no);
                SND_HDA_POWER_SAVE_DEFAULT = lib.mkForce (option no);
                SND_HDA_RECONFIG = lib.mkForce (option no);
                SND_USB_CAIAQ_INPUT = lib.mkForce (option no);
                SONY_FF = lib.mkForce (option no);
                STACK_TRACER = lib.mkForce (option no);
                SUN8I_DE2_CCU = lib.mkForce (option no);
                SUNRPC_DEBUG = lib.mkForce (option no);
                TASK_DELAY_ACCT = lib.mkForce (option no);
                TASK_IO_ACCOUNTING = lib.mkForce (option no);
                TASK_XACCT = lib.mkForce (option no);
                THRUSTMASTER_FF = lib.mkForce (option no);
                USB_XHCI_TEGRA = lib.mkForce (option no);
                VFIO_DEVICE_CDEV = lib.mkForce (option no);
                ZEROPLUS_FF = lib.mkForce (option no);
                ZRAM_BACKEND_842 = lib.mkForce (option no);
                ZRAM_BACKEND_DEFLATE = lib.mkForce (option no);
                ZRAM_BACKEND_LZ4 = lib.mkForce (option no);
                ZRAM_BACKEND_LZ4HC = lib.mkForce (option no);
                ZRAM_BACKEND_LZO = lib.mkForce (option no);
                ZRAM_BACKEND_ZSTD = lib.mkForce (option no);
                ZRAM_DEF_COMP_ZSTD = lib.mkForce (option no);
                ZRAM_MULTI_COMP = lib.mkForce (option no);

                IKHEADERS = no;

                # Profiling-related and other overhead stuff.
                MEM_ALLOC_PROFILING = lib.mkForce no;
                SCHEDSTATS = lib.mkForce no;
                FTRACE = lib.mkForce no;
                KPROBES = lib.mkForce no;
                TASKSTATS = lib.mkForce no;
                NR_CPUS = lib.mkForce (freeform "24");

                # Security modules unused on finit
                SECURITY_APPARMOR = lib.mkForce no;
                IMA = lib.mkForce no;
                SECURITY_IPE = lib.mkForce no;

                # More irrelevant ARM for Apple.
                ARM_SMMU_V3_SVA = lib.mkForce no;
                ARMV8_DEPRECATED = lib.mkForce (option no);
                CHROME_PLATFORMS = lib.mkForce no;
                GOOGLE_FIRMWARE = lib.mkForce no;
                ACPI_HOTPLUG_MEMORY = lib.mkForce no;
                COMPAT_ALIGNMENT_FIXUPS = lib.mkForce (option no);

                # Touch Bar (13" models only); the J314 has none.
                TOUCHSCREEN_APPLE_Z2 = no;

                # Non-Apple Bluetooth; the J314 uses hci_bcm4377 over PCIe.
                BT_HCIBTUSB = no;
                BT_HCIBTSDIO = no;
                BT_HCIUART = lib.mkForce no;
                BT_INTEL_PCIE = no;
                BT_MRVL = no;
                BT_MTKSDIO = no;

                # Arm Mali and Imagination GPUs from the arm64 defconfig.
                DRM_PANTHOR = no;
                DRM_POWERVR = no;

                # Display bridge chips found on other SoC boards.
                DRM_CDNS_MHDP8546 = no;
                DRM_LONTIUM_LT8713SX = no;
                DRM_LONTIUM_LT9611UXC = no;

                # Renesas PCIe USB controller and Microsemi Ethernet PHY.
                USB_XHCI_PCI_RENESAS = no;
                MICROSEMI_PHY = no;

                # Unused storage-related modules.
                IOSCHED_BFQ = lib.mkForce no;
                MQ_IOSCHED_KYBER = lib.mkForce no;
                ZRAM = lib.mkForce no;
                BLK_SED_OPAL = lib.mkForce no;

                # Network filesystems (NFS client/server, SMB) and UDF optical discs.
                NFS_FS = lib.mkForce no;
                NFSD = no;
                CIFS = no;
                UDF_FS = lib.mkForce no;

                # Multipath TCP and link bonding, for servers with several uplinks.
                MPTCP = lib.mkForce no;
                BONDING = lib.mkForce no;

                # sched_ext and BPF LSM need BTF, which is off below; make it explicit.

                # Cheers, BestInfinity.
                DEBUG_INFO_BTF = lib.mkForce no;
                KGDB = no;
                DYNAMIC_DEBUG = lib.mkForce no;

                # Small(?) speed hit.
                CC_OPTIMIZE_FOR_SIZE = lib.mkForce yes;

                # Inline rust/helpers C wrappers in Rust.
                RUST_INLINE_HELPERS = yes;

                # ThinLTO with Clang.
                LTO_NONE = no;
                LTO_CLANG_THIN = yes;

                # Hardening: remove dangerous interfaces.
                DEVMEM = lib.mkForce (option no);
                STRICT_DEVMEM = lib.mkForce (option no);
                IO_STRICT_DEVMEM = lib.mkForce (option no);
                LDISC_AUTOLOAD = lib.mkForce (option no);
                LEGACY_PTYS = lib.mkForce (option no);
                KEXEC = lib.mkForce (option no);
                KEXEC_FILE = lib.mkForce (option no);
                HIBERNATION = lib.mkForce (option no);
                DEBUG_FS = lib.mkForce (option no);
                IO_URING = lib.mkForce (option no);
                # Might break QEMU?
                USERFAULTFD = lib.mkForce (option no);

                # Hardening: mitigations that come from unused features.
                LIST_HARDENING = lib.mkForce (option yes);
                DEBUG_WX = lib.mkForce (option yes);

                # M1 (Pro) has no AArch32 support; with clang the kernel would build it.
                COMPAT = lib.mkForce no;
              };
              features.rust = true;
            }
          ]
          ++ _kernelPatches;
      }
      extraArgs
    );

  linux-asahi = (callPackage linux-asahi-pkg {}).overrideAttrs (o: {
    postInstall =
      (o.postInstall or "")
      + ''
        # Debugging-only symbol map, unrelated to kernel's own.
        rm -f $out/System.map

        # Only keep the J314s (14" M1 Pro) device tree.
        find $out/dtbs -name '*.dtb' ! -name 't6000-j314s.dtb' -delete
        find $out/dtbs -type d -empty -delete
      '';
  });
in
  lib.recurseIntoAttrs (linuxPackagesFor linux-asahi)
