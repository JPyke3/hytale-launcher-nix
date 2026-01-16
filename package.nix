{ pkgs }:

let
  # === AUTO-UPDATE MARKERS - DO NOT MODIFY FORMAT ===
  version = "2026.01.16-2e2291a";
  sha256 = "sha256-bbMQY0v65joTt3nF7/g3Le8wtWGcnpHpWWJ/nm11RXc=";
  # === END AUTO-UPDATE MARKERS ===

  pname = "hytale-launcher";
  downloadUrl = "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-${version}.zip";

  # Unwrapped derivation - extracts and patches the binary
  hytale-launcher-unwrapped = pkgs.stdenv.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version;

    src = pkgs.fetchurl {
      url = downloadUrl;
      inherit sha256;
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      unzip
    ];

    unpackPhase = ''
      runHook preUnpack
      unzip $src -d .
      runHook postUnpack
    '';

    buildInputs = with pkgs; [
      webkitgtk_4_1
      gtk3
      glib
      gdk-pixbuf
      libsoup_3
      cairo
      pango
      at-spi2-atk
      harfbuzz
      glibc
    ];

    runtimeDependencies = with pkgs; [
      libGL
      libxkbcommon
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
    ];

    # No build phase needed - just unpack and install
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/hytale-launcher
      install -m755 hytale-launcher $out/lib/hytale-launcher/

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "Official launcher for Hytale game (unwrapped)";
      homepage = "https://hytale.com";
      license = licenses.unfree;
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      maintainers = [{
        name = "Jacob Pyke";
        email = "github@pyk.ee";
        github = "JPyke3";
        githubId = 13283054;
      }];
      platforms = [ "x86_64-linux" ];
    };
  };

  # FHS-wrapped derivation - allows self-updates to work
  hytale-launcher = pkgs.buildFHSEnv {
    name = "hytale-launcher";
    inherit version;

    targetPkgs = pkgs: with pkgs; [
      # Core dependencies
      hytale-launcher-unwrapped

      # WebKit/GTK stack (for launcher UI)
      webkitgtk_4_1
      gtk3
      glib
      gdk-pixbuf
      libsoup_3
      cairo
      pango
      at-spi2-atk
      harfbuzz

      # Graphics - OpenGL/Vulkan/EGL (for game client via SDL3)
      libGL
      libGLU
      libglvnd
      mesa
      vulkan-loader
      egl-wayland

      # X11 (SDL3 dlopens these)
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXi
      xorg.libxcb
      xorg.libXScrnSaver
      xorg.libXinerama
      xorg.libXxf86vm

      # Wayland (SDL3 can use Wayland backend)
      wayland
      libxkbcommon

      # Audio (for game client via bundled OpenAL)
      alsa-lib
      pipewire
      pulseaudio

      # System libraries
      dbus
      fontconfig
      freetype
      glibc
      nspr
      nss
      systemd
      zlib

      # C++ runtime (needed by libNoesis.so, libopenal.so in game client)
      stdenv.cc.cc.lib

      # .NET runtime dependencies (HytaleClient is a .NET application)
      icu
      openssl
      krb5

      # TLS/SSL support for GLib networking (launcher)
      glib-networking
      cacert
    ];

    runScript = pkgs.writeShellScript "hytale-launcher-wrapper" ''
      # Hytale data directory
      LAUNCHER_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/Hytale"
      LAUNCHER_BIN="$LAUNCHER_DIR/hytale-launcher"
      BUNDLED_HASH_FILE="$LAUNCHER_DIR/.bundled_hash"
      BUNDLED_BIN="${hytale-launcher-unwrapped}/lib/hytale-launcher/hytale-launcher"

      mkdir -p "$LAUNCHER_DIR"

      # Compute hash of bundled binary to detect Nix package updates
      BUNDLED_HASH=$(sha256sum "$BUNDLED_BIN" | cut -d" " -f1)

      # Copy bundled binary if needed (new install or Nix package update)
      if [ ! -x "$LAUNCHER_BIN" ] || [ ! -f "$BUNDLED_HASH_FILE" ] || [ "$(cat "$BUNDLED_HASH_FILE")" != "$BUNDLED_HASH" ]; then
        install -m755 "$BUNDLED_BIN" "$LAUNCHER_BIN"
        echo "$BUNDLED_HASH" > "$BUNDLED_HASH_FILE"
      fi

      # Required environment variable from Flatpak metadata
      export WEBKIT_DISABLE_COMPOSITING_MODE=1

      # Enable GLib TLS backend (glib-networking)
      export GIO_MODULE_DIR=/usr/lib/gio/modules

      # SSL certificates
      export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt

      exec "$LAUNCHER_BIN" "$@"
    '';

    extraInstallCommands = ''
      # Install desktop file
      mkdir -p $out/share/applications
      cat > $out/share/applications/hytale-launcher.desktop << EOF
[Desktop Entry]
Name=Hytale Launcher
Comment=Official launcher for Hytale
Exec=$out/bin/hytale-launcher
Icon=hytale-launcher
Terminal=false
Type=Application
Categories=Game;
Keywords=hytale;game;launcher;hypixel;
StartupWMClass=com.hypixel.HytaleLauncher
EOF

    '';

    meta = with pkgs.lib; {
      description = "Official launcher for Hytale game";
      longDescription = ''
        The official launcher for Hytale, developed by Hypixel Studios.
        This package wraps the launcher from the official distribution,
        providing FHS compatibility for self-updates.
      '';
      homepage = "https://hytale.com";
      license = licenses.unfree;
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      maintainers = [{
        name = "Jacob Pyke";
        email = "github@pyk.ee";
        github = "JPyke3";
        githubId = 13283054;
      }];
      platforms = [ "x86_64-linux" ];
      mainProgram = "hytale-launcher";
    };
  };

in {
  inherit hytale-launcher hytale-launcher-unwrapped;
}
