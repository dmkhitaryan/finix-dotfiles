{
  pkgs,
}:

let
  xresources = pkgs.writeText "urxvt-Xresources" ''
    ! Adwaita Dark-ish
    URxvt.background: #1d1d20
    URxvt.foreground: #ffffff
    URxvt.cursorColor: #ffffff

    ! black
    URxvt.color0:  #241f31
    URxvt.color8:  #5e5c64

    ! red
    URxvt.color1:  #c01c28
    URxvt.color9:  #f66151

    ! green
    URxvt.color2:  #26a269
    URxvt.color10: #8ff0a4

    ! yellow
    URxvt.color3:  #e5a50a
    URxvt.color11: #f9f06b

    ! blue
    URxvt.color4:  #1c71d8
    URxvt.color12: #99c1f1

    ! magenta
    URxvt.color5:  #813d9c
    URxvt.color13: #dc8add

    ! cyan-ish,
    URxvt.color6:  #2ec27e
    URxvt.color14: #57e389

    ! white
    URxvt.color7:  #deddda
    URxvt.color15: #ffffff

    !! URxvt Appearance
    URxvt.letterSpace: 0
    URxvt.lineSpace: 0
    URxvt.geometry: 92x24
    URxvt.internalBorder: 24
    URxvt.cursorBlink: true
    URxvt.cursorUnderline: false
    URxvt.saveline: 2048
    URxvt.scrollBar: false
    URxvt.scrollBar_right: false
    URxvt.urgentOnBell: true
    URxvt.depth: 24
    URxvt.iso14755: false
    URxvt.iso14755_52: false

    URxvt.font:           xft:Terminus (TTF):pixelsize=16:style=Medium,\
                          xft:Font Awesome 6 Free:style=Solid:pixelsize=16
    URxvt.boldFont:       xft:Terminus (TTF):pixelsize=16:style=Bold
    URxvt.italicFont:     xft:Terminus (TTF):pixelsize=16:style=Italic
    URxvt.boldItalicFont: xft:Terminus (TTF):pixelsize=16:style=Bold-Italic

    URxvt.perl-ext-common: default,clipboard
    URxvt.keysym.Control-Shift-V: perl:clipboard:paste
    URxvt.keysym.Control-Shift-C: perl:clipboard:copy
  '';

  rxvt-unicode = pkgs.rxvt-unicode.override {
    configure = { availablePlugins, ... }: {
      plugins = with availablePlugins; [
        perls
        resize-font
        vtwheel
      ];
    };
  };
in
pkgs.symlinkJoin {
  name = "rxvt-unicode-wrapped-${rxvt-unicode.version}";
  paths = [ rxvt-unicode ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    for program in urxvt urxvtc urxvtd; do
      wrapProgram "$out/bin/$program" --set XENVIRONMENT ${xresources}
    done
  '';
  meta.mainProgram = "urxvt";
}
