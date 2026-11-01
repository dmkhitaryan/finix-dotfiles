# Epiphany (GNOME Web), trimmed to what its meson.build actually needs.
# Based on nixpkgs' pkgs/by-name/ep/epiphany, checked against upstream 51.1.
#
# Dropped vs nixpkgs:
#   gnome-desktop, icu    - not referenced by meson.build at all
#   docutils              - only for man pages (-Dman-pages=disabled)
#   itstool               - only for the yelp help pages (subdir removed)
#   gst-plugins-bad/ugly  - not needed here; WebKit pulls in (our slimmed) bad itself
{
  lib,
  stdenv,
  fetchurl,
  # build
  blueprint-compiler,
  desktop-file-utils,
  gettext,
  meson,
  ninja,
  pkg-config,
  wrapGAppsHook4,
  buildPackages,
  # libraries (each matches a dependency() in meson.build)
  gcr_4, # gcr-4, gck-2
  gdk-pixbuf,
  glib,
  gsettings-desktop-schemas,
  gtk4, # gtk4, gtk4-unix-print, cairo
  isocodes,
  json-glib,
  libadwaita,
  libarchive,
  libportal-gtk4,
  libpwquality, # pwquality (new in 51)
  libsecret,
  libsoup_3,
  libxml2,
  nettle, # nettle, hogweed
  sqlite,
  webkitgtk_6_0,
  gst_all_1, # gstreamer-1.0 at build time; plugins are for WebKit media at runtime
  # runtime only
  glib-networking, # TLS for libsoup
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "epiphany";
  version = "51.1";

  src = fetchurl {
    url = "mirror://gnome/sources/epiphany/${lib.versions.major finalAttrs.version}/epiphany-${finalAttrs.version}.tar.xz";
    hash = "sha256-vrk7O4a3YwkqEXW25QV4m3YTBxwNwa1WysGXn+h56d0=";
  };

  # Help pages go through gnome.yelp unconditionally, which needs itstool (python).
  postPatch = ''
    substituteInPlace meson.build --replace-fail "subdir('help')" ""
  '';

  nativeBuildInputs = [
    blueprint-compiler
    desktop-file-utils
    gettext
    meson
    ninja
    pkg-config
    wrapGAppsHook4
    buildPackages.glib # glib-mkenums, glib-compile-schemas
    buildPackages.gtk4 # gtk4-update-icon-cache
  ];

  buildInputs = [
    gcr_4
    gdk-pixbuf
    glib
    glib-networking
    gsettings-desktop-schemas
    gtk4
    isocodes
    json-glib
    libadwaita
    libarchive
    libportal-gtk4
    libpwquality
    libsecret
    libsoup_3
    libxml2
    nettle
    sqlite
    webkitgtk_6_0
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-libav
  ];

  mesonFlags = [
    "-Dunit_tests=disabled" # need a display
    "-Dman-pages=disabled"
  ];

  meta = {
    homepage = "https://apps.gnome.org/Epiphany/";
    description = "WebKit based web browser for GNOME (trimmed)";
    mainProgram = "epiphany";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
