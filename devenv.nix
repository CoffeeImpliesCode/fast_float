# Tools and tasks only; package outputs build on demand.
{ pkgs, ... }:

let
  # Use the Zig release required by build.zig.zon.
  zig = pkgs.zig_0_17;

  mk = linkage: pkgs.callPackage ./package.nix { inherit zig linkage; };

  # Resolve task roots from this file because task bodies inherit the caller's working directory.
  sdkRoot = pkgs.lib.escapeShellArg (builtins.toString ./.);
  consumerRoot = pkgs.lib.escapeShellArg (builtins.toString ./. + "/consumer");

  # Resolve both caches inside each task; single-task mode skips enterShell.
  # Preserve caller-provided cache paths and keep generated caches outside the source tree.
  cacheDirs = ''
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/zig-global"
      elif [ -n "''${TMPDIR:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
      else
        echo "fast_float: ZIG_GLOBAL_CACHE_DIR is unset and neither XDG_CACHE_HOME nor TMPDIR is set, so no cache outside this tree is known. Export one of them." >&2
        exit 1
      fi
      export ZIG_GLOBAL_CACHE_DIR
    fi
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/zig-local"
      elif [ -n "''${TMPDIR:-}" ]; then
        ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
      else
        echo "fast_float: ZIG_LOCAL_CACHE_DIR is unset and neither XDG_CACHE_HOME nor TMPDIR is set, so no cache outside this tree is known. Export one of them, or set PREFIX for sdk:install." >&2
        exit 1
      fi
      export ZIG_LOCAL_CACHE_DIR
    fi
  '';

  # Bind the static output before the output set to avoid recursive attribute lookup.
  fastFloatStatic = mk "static";
in
{
  packages = [
    zig
    pkgs.pkg-config
  ];

  outputs = {
    static = fastFloatStatic;
    shared = mk "dynamic";
    default = fastFloatStatic;
  };

  enterShell = ''
    # Set cache defaults only when the caller has not provided them.
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ] && [ -n "''${XDG_CACHE_HOME:-}" ]; then
      export ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/zig-global"
    fi
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] && [ -n "''${XDG_CACHE_HOME:-}" ]; then
      export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/zig-local"
    fi
  '';

  tasks = {
    "sdk:install".description =
      "zig build install into a prefix outside this tree (set PREFIX to override)";
    "sdk:install".exec = ''
      cd ${sdkRoot} || exit 1
      ${cacheDirs}
      # Default the install prefix under the Zig cache; PREFIX can override it.
      mkdir -p "''${PREFIX:=$ZIG_LOCAL_CACHE_DIR/fast_float-install}"
      zig build install --prefix "$PREFIX" -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"
    '';

    "sdk:test".description = "zig build test; pass -Dtarget=... to cross";
    "sdk:test".exec = ''
      cd ${sdkRoot} || exit 1
      ${cacheDirs}
      zig build test -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"
    '';

    "sdk:smoke".description = "zig build smoke: the example that checks its own answers";
    "sdk:smoke".exec = ''
      cd ${sdkRoot} || exit 1
      ${cacheDirs}
      zig build smoke -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"
    '';

    "sdk:check".description = "zig build check: compile-only over the six required targets";
    "sdk:check".exec = ''
      cd ${sdkRoot} || exit 1
      ${cacheDirs}
      zig build check -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"
    '';

    "sdk:consumer".description = "build and run the separate consumer package against this tree";
    "sdk:consumer".exec = ''
      cd ${consumerRoot} || exit 1
      ${cacheDirs}
      zig build run -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR" "$@"
    '';

    "provenance:integrity".description =
      "sha256sum -c UPSTREAM.sha256 over the 73 immutable upstream and donor bytes";
    "provenance:integrity".exec = ''
      cd ${sdkRoot} || exit 1
      sha256sum -c UPSTREAM.sha256
    '';

    "package:static".description = "devenv build outputs.static";
    "package:static".exec = ''devenv build outputs.static "$@"'';

    "package:shared".description = "devenv build outputs.shared";
    "package:shared".exec = ''devenv build outputs.shared "$@"'';
  };
}