{
  pkgs,
}:

let
  preferencesStatus = "user";
  xdg-utils = pkgs.callPackage ../../xdg-utils-perlless.nix { };

  wrapFirefox = pkgs.wrapFirefox.override {
    inherit xdg-utils;
  };

  preferences = {
      # Betterfox
      # "Ad meliora"
      # version: 150
      # url: https://github.com/yokoffing/Betterfox

      # v152 FASTFOX
      "gfx.content.skia-font-cache-size" = 20;
      "content.notify.interval" = 100000;
      "gfx.canvas.accelerated.cache-size" = 512;
      "javascript.options.baselinejit.threshold" = 50;
      "media.cache_readahead_limit" = 3600;
      "media.cache_resume_threshold" = 1800;
      "image.mem.decode_bytes_at_a_time" = 32768;
      "network.buffer.cache.size" = 65535;
      "network.buffer.cache.count" = 48;
      "network.http.max-connections" = 1800;
      "network.http.max-persistent-connections-per-server" = 10;
      "network.http.max-urgent-start-excessive-connections-per-host" = 5;
      "network.http.request.max-start-delay" = 5;
      "network.dnsCacheExpiration" = 3600;

      # SECTION: SECUREFOX

      # TRACKING PROTECTION
      "browser.contentblocking.category" = "strict";
      "browser.download.start_downloads_in_tmp_dir" = true;
      "browser.uitour.enabled" = false;
      "privacy.globalprivacycontrol.enabled" = true;

      # OCSP & CERTS / HPKP
      "security.OCSP.enabled" = 0;
      "privacy.antitracking.isolateContentScriptResources" = true;
      "security.csp.reporting.enabled" = false;

      # SSL / TLS
      "security.ssl.treat_unsafe_negotiation_as_broken" = true;
      "browser.xul.error_pages.expert_bad_cert" = true;
      "security.tls.enable_0rtt_data" = false;

      # DISK AVOIDANCE
      "browser.cache.disk.enable" = false;
      "browser.privatebrowsing.forceMediaMemoryCache" = true;
      "media.memory_cache_max_size" = 65536;
      "browser.sessionstore.interval" = 60000;

      # SHUTDOWN & SANITIZING
      "privacy.history.custom" = true;

      # SPECULATIVE LOADING
      "network.http.speculative-parallel-limit" = 0;
      "network.dns.disablePrefetch" = true;
      "network.dns.disablePrefetchFromHTTPS" = true;
      "browser.urlbar.speculativeConnect.enabled" = false;
      "browser.places.speculativeConnect.enabled" = false;
      "network.prefetch-next" = false;

      # SEARCH / URL BAR
      "browser.urlbar.trimHttps" = true;
      "browser.urlbar.untrimOnUserInteraction.featureGate" = true;
      "browser.search.separatePrivateDefault.ui.enabled" = true;
      "browser.search.suggest.enabled" = false;
      "browser.urlbar.quicksuggest.enabled" = false;
      "browser.urlbar.groupLabels.enabled" = false;
      "browser.formfill.enable" = false;
      "network.IDN_show_punycode" = true;

      # HTTPS-ONLY MODE
      "dom.security.https_only_mode" = true;
      "dom.security.https_only_mode_error_page_user_suggestions" = true;

      # PASSWORDS
      "signon.formlessCapture.enabled" = false;
      "signon.privateBrowsingCapture.enabled" = false;
      "network.auth.subresource-http-auth-allow" = 1;
      "editor.truncate_user_pastes" = false;

      # EXTENSIONS
      "extensions.enabledScopes" = 5;

      # HEADERS / REFERERS
      "network.http.referer.XOriginTrimmingPolicy" = 2;

      # CONTAINERS
      "privacy.userContext.ui.enabled" = true;

      # VARIOUS
      "pdfjs.enableScripting" = false;

      # SAFE BROWSING
      "browser.safebrowsing.downloads.remote.enabled" = false;

      # MOZILLA
      "permissions.default.desktop-notification" = 2;
      "permissions.default.geo" = 0;
      "geo.provider.network.url" = "https://beacondb.net/v1/geolocate";
      "browser.search.update" = false;
      "permissions.manager.defaultsUrl" = "";
      "extensions.getAddons.cache.enabled" = false;

      # TELEMETRY
      "datareporting.policy.dataSubmissionEnabled" = false;
      "datareporting.healthreport.uploadEnabled" = false;
      "toolkit.telemetry.unified" = false;
      "toolkit.telemetry.enabled" = false;
      "toolkit.telemetry.server" = "data:,";
      "toolkit.telemetry.archive.enabled" = false;
      "toolkit.telemetry.newProfilePing.enabled" = false;
      "toolkit.telemetry.shutdownPingSender.enabled" = false;
      "toolkit.telemetry.updatePing.enabled" = false;
      "toolkit.telemetry.bhrPing.enabled" = false;
      "toolkit.telemetry.firstShutdownPing.enabled" = false;
      "toolkit.telemetry.coverage.opt-out" = true;
      "toolkit.coverage.opt-out" = true;
      "toolkit.coverage.endpoint.base" = "";
      "browser.newtabpage.activity-stream.telemetry" = false;
      "datareporting.usage.uploadEnabled" = false;

      # EXPERIMENTS
      "app.shield.optoutstudies.enabled" = false;
      "app.normandy.enabled" = false;
      "app.normandy.api_url" = "";

      # CRASH REPORTS
      "breakpad.reportURL" = "";
      "browser.tabs.crashReporting.sendReport" = false;

      # SECTION: PESKYFOX

      # MOZILLA UI
      "extensions.getAddons.showPane" = false;
      "extensions.htmlaboutaddons.recommendations.enabled" = false;
      "browser.discovery.enabled" = false;
      "browser.shell.checkDefaultBrowser" = false;
      "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
      "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
      "browser.preferences.moreFromMozilla" = false;
      "browser.aboutConfig.showWarning" = false;
      "browser.startup.homepage_override.mstone" = "ignore";
      "browser.aboutwelcome.enabled" = false;
      "browser.profiles.enabled" = true;

      # THEME ADJUSTMENTS
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      "browser.compactmode.show" = true;
      "browser.privateWindowSeparation.enabled" = false; # WINDOWS

      # AI
      "browser.ai.control.default" = "blocked";
      "browser.ml.enable" = false;
      "browser.ml.chat.enabled" = false;
      "browser.ml.chat.menu" = false;
      "browser.tabs.groups.smart.enabled" = false;
      "browser.ml.linkPreview.enabled" = false;

      # FULLSCREEN NOTICE
      "full-screen-api.transition-duration.enter" = "0 0";
      "full-screen-api.transition-duration.leave" = "0 0";
      "full-screen-api.warning.timeout" = 0;

      # URL BAR
      "browser.urlbar.trending.featureGate" = false;

      # NEW TAB PAGE
      "browser.newtabpage.activity-stream.feeds.topsites" = true;
      "browser.newtabpage.activity-stream.default.sites" = "";
      "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
      "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
      "browser.newtabpage.activity-stream.showSponsored" = false;
      "browser.newtabpage.activity-stream.showSponsoredCheckboxes" = false;

      # DOWNLOADS
      "browser.download.manager.addToRecentDocs" = false;

      # PDF
      "browser.download.open_pdf_attachments_inline" = true;

      # TAB BEHAVIOR
      "browser.bookmarks.openInTabClosesMenu" = false;
      "findbar.highlightAll" = true;

      # SECTION: SMOOTHFOX

      # visit https://github.com/yokoffing/Betterfox/blob/main/Smoothfox.js
      # Enter your scrolling overrides below this line:

      # START: MY OVERRIDES

      # visit https://github.com/yokoffing/Betterfox/wiki/Common-Overrides
      # visit https://github.com/yokoffing/Betterfox/wiki/Optional-Hardening
      # Enter your personal overrides below this line:

      # PREF: set DoH provider
      "network.trr.uri" = "https://dns.dnswarden.com/00000000000000000000028"; # Hagezi Normal + TIF

      # PREF: enforce DNS-over-HTTPS (DoH)
      "network.trr.mode" = 2;
      "network.trr.max-fails" = 5;

      # PREF: display the installation prompt for all extensions
      "extensions.postDownloadThirdPartyPrompt" = false;

      # PREF: enforce certificate pinning
      # [ERROR] MOZILLA_PKIX_ERROR_KEY_PINNING_FAILURE
      # 1 = allow user MiTM, such as your antivirus, default
      # 2 = strict
      "security.cert_pinning.enforcement_level" = 2;

      # PREF: delete cookies, cache, and site data on shutdown
      "privacy.sanitize.sanitizeOnShutdown" = true;
      "privacy.clearOnShutdown_v2.browsingHistoryAndDownloads" = false; # Browsing & download history
      "privacy.clearOnShutdown_v2.cookiesAndStorage" = false; # Cookies and site data
      "privacy.clearOnShutdown_v2.cache" = true; # Temporary cached files and pages
      "privacy.clearOnShutdown_v2.formdata" = true; # Saved form info

      # PREF: disable service workers
      # This will break push notifications, blocked in Betterfox by default.
      "dom.serviceWorkers.enabled" = true;
      "dom.serviceWorkers.privateBrowsing.enabled" = true;

      # PREF: disable JIT compliation
      # WARNING: Some sites may malfunction.
      "javascript.options.ion" = true;
      "javascript.options.baselinejit" = true; # turn to "true" if too bad.
      "javascript.options.wasm_optimizingjit" = true;

      # Start reacting when free/available memory gets relatively low.
      "browser.low_commit_space_threshold_mb" = 4096;
      "browser.low_commit_space_threshold_percent" = 25;

      # Actually allow low-memory tab unloading.
      "browser.tabs.unloadOnLowMemory" = true;

      # END: BETTERFOX
  };

in
rec {
  default = firefox;
  firefox = wrapFirefox pkgs.firefox-bin-unwrapped {
    extraPolicies = {
      Preferences = builtins.mapAttrs (_: value: {
        Value = value;
        Status = preferencesStatus;
      }) preferences;
    };
  };
}
