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

        # Whitelist: start from nothing, list only what the J314s uses.
        defconfig = "allnoconfig";
        enableCommonConfig = false;
        autoModules = false;
        ignoreConfigErrors = false;
        extraMakeFlags = ["LLVM_LINK=${llvmPackages.llvm}/bin/llvm-link"];

        kernelPatches =
          [
            {
              name = "necomac whitelist";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                # ---------------------------------------------------------
                # Base
                # ---------------------------------------------------------
                EXPERT = yes;

                ARCH_APPLE = yes;
                ARM64_16K_PAGES = yes;
                ARM64_VA_BITS_47 = option yes; # M1 has no LPA2.
                NR_CPUS = freeform "10"; # 8P + 2E
                SCHED_MC = yes;
                SCHED_CLUSTER = yes;
                SCHED_AUTOGROUP = yes;
                NO_HZ_IDLE = yes;
                HIGH_RES_TIMERS = yes;
                PREEMPT_LAZY = yes;

                ARM64_MEMORY_MODEL_CONTROL = yes;
                ARM64_ACTLR_STATE = yes;
                ARM64_HW_AFDBM = yes;
                ARM64_TLB_RANGE = option yes;

                RUST = yes;
                RUST_INLINE_HELPERS = yes;
                LTO_CLANG_THIN = yes;
                CC_OPTIMIZE_FOR_SIZE = yes;
                SECTION_MISMATCH_WARN_ONLY = yes;

                MODULES = yes;
                MODULE_UNLOAD = yes;
                MODULE_COMPRESS = yes;
                MODULE_COMPRESS_ZSTD = yes; # Instead of default(?) XZ.
                MODULE_COMPRESS_ALL = yes;
                # MODULE_SIG is dropped (Signs every module with SHA512, but not enforced).

                KERNEL_ZSTD = yes;
                BLK_DEV_INITRD = yes;
                RD_ZSTD = yes;

                IKCONFIG = yes;
                IKCONFIG_PROC = yes;
                PRINTK_TIME = yes;
                MAGIC_SYSRQ = yes;

                EFI = yes;
                EFI_STUB = yes;
                EFI_ZBOOT = yes;
                SYSFB_SIMPLEFB = yes;

                FW_LOADER = yes;
                FW_LOADER_COMPRESS = yes;
                FW_LOADER_COMPRESS_XZ = yes;
                FW_LOADER_COMPRESS_ZSTD = yes;
                FW_CACHE = yes;

                # Optional debug UART + `earlycon`.
                # SERIAL_SAMSUNG = yes;
                # SERIAL_SAMSUNG_CONSOLE = yes;
                # SERIAL_EARLYCON = yes;

                # ---------------------------------------------------------
                # Hardening (allnoconfig turns all of this off)
                # ---------------------------------------------------------
                CPU_MITIGATIONS = yes;
                UNMAP_KERNEL_AT_EL0 = yes;
                MITIGATE_SPECTRE_BRANCH_HISTORY = option yes;
                RANDOMIZE_BASE = yes;
                RELR = yes;
                RANDOMIZE_MODULE_REGION_FULL = yes;
                RANDOMIZE_KSTACK_OFFSET = option yes;
                RANDOMIZE_KSTACK_OFFSET_DEFAULT = yes;
                VMAP_STACK = yes;
                STACKPROTECTOR = yes;
                STACKPROTECTOR_STRONG = yes;
                ARM64_PTR_AUTH = yes;
                ARM64_PTR_AUTH_KERNEL = yes;
                HARDENED_USERCOPY = yes;
                FORTIFY_SOURCE = yes;
                INIT_STACK_ALL_ZERO = yes;
                INIT_ON_ALLOC_DEFAULT_ON = yes;
                SLAB_FREELIST_RANDOM = yes;
                SLAB_FREELIST_HARDENED = yes;
                SLAB_BUCKETS = yes;
                KMALLOC_PARTITION_CACHES = yes;
                KMALLOC_PARTITION_RANDOM = yes;
                SHUFFLE_PAGE_ALLOCATOR = yes;
                LIST_HARDENED = yes;
                BUG_ON_DATA_CORRUPTION = yes;
                SCHED_STACK_END_CHECK = yes;
                DEBUG_WX = option yes;
                SECCOMP = yes;
                SECURITY = yes;
                SECURITY_YAMA = yes;
                SECURITY_LANDLOCK = yes;
                SECURITY_DMESG_RESTRICT = yes;

                # ---------------------------------------------------------
                # Userland: finit, mdevd, seatd, Nix sandbox, Xwayland, Firefox
                # ---------------------------------------------------------
                SYSVIPC = yes;
                POSIX_MQUEUE = yes;
                CROSS_MEMORY_ATTACH = yes;
                INOTIFY_USER = yes;
                BINFMT_ELF = yes;
                BINFMT_SCRIPT = yes;
                DEVTMPFS = yes;
                DEVTMPFS_MOUNT = yes;
                TMPFS = yes;
                TMPFS_POSIX_ACL = yes;
                TMPFS_XATTR = yes;

                CGROUPS = yes;
                CGROUP_SCHED = yes;
                FAIR_GROUP_SCHED = yes;
                MEMCG = yes;
                CPUSETS = yes;
                CGROUP_PIDS = yes;
                PSI = yes;

                NAMESPACES = yes;
                UTS_NS = yes;
                IPC_NS = yes;
                USER_NS = yes;
                PID_NS = yes;
                NET_NS = yes;

                # ---------------------------------------------------------
                # Memory
                # ---------------------------------------------------------
                SWAP = yes;
                ZSWAP = yes;
                ZSMALLOC = yes;
                ZSWAP_COMPRESSOR_DEFAULT_ZSTD = option yes;
                CRYPTO_ZSTD = yes;
                COMPACTION = yes;
                TRANSPARENT_HUGEPAGE = yes;
                TRANSPARENT_HUGEPAGE_MADVISE = yes;
                LRU_GEN = yes;
                LRU_GEN_ENABLED = option yes;

                # ---------------------------------------------------------
                # Power
                # ---------------------------------------------------------
                PM = yes;
                SUSPEND = yes;
                ENERGY_MODEL = yes;
                WQ_POWER_EFFICIENT_DEFAULT = yes;
                CPU_FREQ = yes;
                CPU_FREQ_GOV_SCHEDUTIL = yes;
                CPU_FREQ_DEFAULT_GOV_SCHEDUTIL = yes;
                ARM_APPLE_SOC_CPUFREQ = yes;
                CPU_IDLE = yes;
                ARM_APPLE_CPUIDLE = yes;
                ARM_ARCH_TIMER_EVTSTREAM = yes;

                # ---------------------------------------------------------
                # Apple SoC platform
                # ---------------------------------------------------------
                IOMMU_SUPPORT = yes;
                APPLE_DART = yes;
                MAILBOX = yes;
                APPLE_MAILBOX = yes;
                APPLE_RTKIT = yes;
                RUST_APPLE_RTKIT = yes;
                APPLE_SART = yes;
                APPLE_PMGR_PWRSTATE = yes;
                APPLE_PMGR_MISC = yes;
                APPLE_PMP = yes; # apple-use-pmp.patch
                APPLE_PMP_REPORT = option yes;
                APPLE_TUNABLE = module;
                APPLE_AOP = yes;
                WATCHDOG = yes;
                APPLE_WATCHDOG = yes;
                PERF_EVENTS = yes;
                APPLE_M1_CPU_PMU = yes;

                PINCTRL = yes;
                PINCTRL_APPLE_GPIO = module;
                GPIOLIB = yes;
                GPIO_SHARED_PROXY = option module; # 6 devices depend on this as a module.
                I2C = yes;
                I2C_APPLE = module;
                SPI = yes;
                SPI_APPLE = module;
                SPMI = yes;
                SPMI_APPLE = module;
                NVMEM = yes;
                NVMEM_APPLE_SPMI = module;
                PWM = yes;
                PWM_APPLE = module;
                NEW_LEDS = yes;
                LEDS_CLASS = yes;
                LEDS_PWM = module;
                COMMON_CLK_APPLE_NCO = module;
                DMADEVICES = yes;
                APPLE_SIO = module;
                APPLE_ADMAC = module;
                GENERIC_PHY = yes;
                PHY_APPLE_ATC = module;
                MULTIPLEXER = yes;
                MUX_APPLE_DPXBAR = module;
                MUX_CORE = yes;

                # SMC
                MFD_MACSMC = module;
                GPIO_MACSMC = module;
                HWMON = yes;
                SENSORS_MACSMC_HWMON = module;
                INPUT_MISC = yes;
                INPUT_MACSMC_INPUT = module;
                POWER_SUPPLY = yes;
                MACSMC_POWER = module;
                POWER_RESET = yes;
                POWER_RESET_MACSMC = module;
                RTC_CLASS = yes;
                RTC_DRV_MACSMC = module;

                # Ambient light / lid angle
                IIO = yes;
                IIO_AOP_SENSOR_ALS = module;
                IIO_AOP_SENSOR_LAS = module;

                # ---------------------------------------------------------
                # Storage / filesystems
                # ---------------------------------------------------------
                BLK_WBT = yes;
                NVME_APPLE = yes;
                PCI = yes;
                PCIEPORTBUS = yes;
                PCIE_APPLE = module;

                MMC = yes;
                MMC_BLOCK = yes;
                MMC_SDHCI = yes;
                MMC_SDHCI_PCI = module;

                SCSI = yes;
                BLK_DEV_SD = yes;

                EXT4_FS = yes;
                EXT4_FS_POSIX_ACL = yes;
                VFAT_FS = yes;
                NLS = yes;
                NLS_CODEPAGE_437 = yes;
                NLS_ISO8859_1 = yes;
                NLS_UTF8 = module;
                EXFAT_FS = module;
                FUSE_FS = module;

                # ---------------------------------------------------------
                # USB / USB-C
                # ---------------------------------------------------------
                USB_SUPPORT = yes;
                USB = yes;
                USB_XHCI_HCD = yes;
                USB_XHCI_PLATFORM = yes;
                USB_DWC3 = yes;
                USB_DWC3_APPLE = yes;
                # TODO:
                # try USB_DWC3_HOST and drop USB_GADGET;
                # see if ports still work without it.
                USB_GADGET = yes;
                USB_DWC3_DUAL_ROLE = yes;
                USB_ROLE_SWITCH = yes;
                USB_STORAGE = yes;
                USB_UAS = module;
                TYPEC = module;
                TYPEC_TPS6598X = module;
                TYPEC_DP_ALTMODE = module;
                USB4 = module;
                USB4_APPLE_SOC = module;
                RESET_APPLE_CIO = module;

                NETDEVICES = yes;
                USB_NET_DRIVERS = yes;
                USB_USBNET = module;
                USB_NET_CDCETHER = module;
                USB_NET_CDC_NCM = module;
                USB_RTL8152 = module;
                USB_NET_AX88179_178A = module;

                # ---------------------------------------------------------
                # Input
                # ---------------------------------------------------------
                INPUT = yes;
                INPUT_EVDEV = yes;
                HID = yes;
                HID_GENERIC = yes;
                HID_SUPPORT = yes;
                HID_MULTITOUCH = module;
                HIDRAW = yes;
                HID_BATTERY_STRENGTH = yes;
                USB_HID = yes;
                HID_APPLE = module;
                HID_MAGICMOUSE = module;
                SPI_HID_APPLE_OF = module;
                UHID = module;
                INPUT_UINPUT = yes;

                # ---------------------------------------------------------
                # Display / GPU
                # ---------------------------------------------------------
                DRM = yes;
                DRM_ASAHI = yes;
                DRM_APPLE = module;
                DRM_APPLE_AUDIO = yes;
                DRM_SIMPLEDRM = yes;
                DRM_FBDEV_EMULATION = yes;
                FRAMEBUFFER_CONSOLE = yes;
                BACKLIGHT_CLASS_DEVICE = yes;
                VT_CONSOLE = yes;
                FONTS = yes;
                FONT_8x16 = yes;
                FONT_TER16x32 = yes;

                # ---------------------------------------------------------
                # Sound
                # ---------------------------------------------------------
                SOUND = module;
                SND = module;
                SND_DYNAMIC_MINORS = yes;
                SND_SOC = module;
                SND_SOC_APPLE_MCA = module;
                SND_SOC_APPLE_MACAUDIO = module;
                SND_SOC_APPLE_AOP_AUDIO = module;
                SND_SOC_TAS2764 = module;
                SND_SOC_CS42L84 = module;
                SND_USB = yes;
                SND_USB_AUDIO = module;
                SND_USB_AUDIO_MIDI_V2 = no;

                # ---------------------------------------------------------
                # Camera / video decoder
                # ---------------------------------------------------------
                MEDIA_SUPPORT = module;
                MEDIA_SUPPORT_FILTER = yes;
                MEDIA_SUBDRV_AUTOSELECT = no;
                MEDIA_CAMERA_SUPPORT = yes;
                MEDIA_PLATFORM_SUPPORT = yes;
                MEDIA_CONTROLLER = yes;
                MEDIA_PLATFORM_DRIVERS = yes;
                V4L_PLATFORM_DRIVERS = yes;
                V4L_MEM2MEM_DRIVERS = yes;
                VIDEO_DEV = module;
                VIDEO_APPLE_ISP = module;
                VIDEO_APPLE_AVD = module;

                # ---------------------------------------------------------
                # Network, Wi-Fi, Bluetooth
                # ---------------------------------------------------------
                NET = yes;
                UNIX = yes;
                PACKET = yes;
                INET = yes;
                IP_MULTICAST = yes;
                IPV6 = yes;
                TUN = module;

                IP_ADVANCED_ROUTER = yes;
                IP_MULTIPLE_TABLES = yes;
                IPV6_MULTIPLE_TABLES = yes;
                WIREGUARD = module;

                NET_SCHED = yes;
                NET_SCH_FQ_CODEL = yes;
                NET_SCH_DEFAULT = yes;
                DEFAULT_FQ_CODEL = yes;

                WIRELESS = yes;
                CFG80211 = module;
                RFKILL = module;
                WLAN = yes;
                WLAN_VENDOR_BROADCOM = yes;
                BRCMFMAC = module;
                BRCMFMAC_PCIE = yes;

                BT = module;
                BT_BREDR = yes;
                BT_LE = yes;
                BT_RFCOMM = module;
                BT_HIDP = module;
                BT_HCIBCM4377 = module;

                # iwd: AF_ALG, keyring, certificates
                KEYS = yes;
                KEY_DH_OPERATIONS = yes;
                ASYMMETRIC_KEY_TYPE = yes;
                ASYMMETRIC_PUBLIC_KEY_SUBTYPE = yes;
                X509_CERTIFICATE_PARSER = yes;
                PKCS7_MESSAGE_PARSER = yes;
                PKCS8_PRIVATE_KEY_PARSER = yes;
                CRYPTO_USER_API_HASH = module;
                CRYPTO_USER_API_SKCIPHER = module;
                CRYPTO_USER_API_AEAD = module;
                CRYPTO_AES = yes;
                CRYPTO_CBC = yes;
                CRYPTO_ECB = yes;
                CRYPTO_CMAC = yes;
                CRYPTO_HMAC = yes;
                CRYPTO_SHA1 = yes;
                CRYPTO_SHA256 = yes;
                CRYPTO_SHA512 = yes;
                CRYPTO_SHA3 = module;
                CRYPTO_MD4 = module;
                CRYPTO_MD5 = module;
                CRYPTO_DES = module;
                CRYPTO_ECDH = module;

                # Arm64 CE acceleration
                CRYPTO_AES_ARM64_CE_BLK = yes;
                CRYPTO_AES_ARM64_CE_CCM = yes;
                CRYPTO_GHASH_ARM64_CE = yes;

                # ---------------------------------------------------------
                # Virtualisation
                # ---------------------------------------------------------
                VIRTUALIZATION = yes;
                KVM = yes;
                VHOST_MENU = yes;
                VSOCKETS = module;
                VHOST_NET = module;
                VHOST_VSOCK = module;

                # ---------------------------------------------------------
                # Docker
                # ---------------------------------------------------------
                # Container networking
                VETH = module;
                BRIDGE = module;
                BRIDGE_NETFILTER = module;

                # Storage (overlay2)
                OVERLAY_FS = module;

                # cgroups: device rules (eBPF), resource limits
                BPF_SYSCALL = yes;
                CGROUP_BPF = yes;
                CGROUP_DEVICE = yes;
                CGROUP_CPUACCT = yes;
                CGROUP_FREEZER = yes;
                CFS_BANDWIDTH = yes;
                BLK_CGROUP = yes;
                BLK_DEV_THROTTLING = yes;

                # NAT and port publishing via iptables-nft
                NETFILTER = yes;
                NETFILTER_ADVANCED = yes;
                NF_CONNTRACK = module;
                NF_NAT = module;
                NF_TABLES = module;
                NF_TABLES_INET = yes;
                NF_TABLES_IPV4 = yes;
                NF_TABLES_IPV6 = yes;
                NFT_COMPAT = module;
                NFT_CT = module;
                NFT_NAT = module;
                NFT_MASQ = module;
                NETFILTER_XTABLES = module;
                NETFILTER_XT_MARK = module;
                NETFILTER_XT_NAT = module;
                NETFILTER_XT_TARGET_MASQUERADE = module;
                NETFILTER_XT_MATCH_ADDRTYPE = module;
                NETFILTER_XT_MATCH_CONNTRACK = module;
                IP_NF_IPTABLES = module;
                IP6_NF_IPTABLES = module;

                # ---------------------------------------------------------
                # Worth considering?
                # ---------------------------------------------------------
                # USB webcams
                # MEDIA_USB_SUPPORT = yes;
                # USB_VIDEO_CLASS = module;

                # USB serial devices
                # USB_ACM = module;
                # USB_SERIAL = module;
                # USB_SERIAL_CH341 = module;
                # USB_SERIAL_CP210X = module;
                # USB_SERIAL_FTDI_SIO = module;
                # USB_SERIAL_PL2303 = module;

                # HID_MULTITOUCH = module;
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
