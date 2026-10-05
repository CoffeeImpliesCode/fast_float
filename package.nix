# Standalone source-only derivation for the fast_float Zig SDK.
#
# One uncurried function returning ONE derivation. `flake.nix` and `devenv.nix`
# both call it through `pkgs.callPackage` with `zig = pkgs.zig_0_16`, so the two
# entry points cannot drift and the linkage variants stay one SDK.
#
# The build graph owns the C++ flags, the source list and every install path.
# This file sets only delivery: prefix, optimize, CPU baseline and linkage.
{
  lib
, stdenv
, zig
, linkage ? "static"
, extraNativeBuildInputs ? [ ]
}:

assert lib.assertMsg (linkage == "static" || linkage == "dynamic")
  "fast_float: linkage must be \"static\" or \"dynamic\", got \"${toString linkage}\"";

let
  # Upstream's own version: CMakeLists.txt:4 and FASTFLOAT_VERSION_* at
  # include/fast_float/float_common.h:19-21. Same string as build.zig.zon
  # `.version`; the derivation needs it only for `src`'s name and `meta`.
  version = "8.3.0";

  # VCS metadata, build products and development state. Everything a build
  # compiles or a test reads is kept, including the 262 MB known-answer corpus
  # in testdata/, which `zig build test` reads from disk at run time.
  dropped = [
    ".git"
    ".devenv"
    ".devenv.flakes"
    ".devenv.flake.nix"
    ".direnv"
    ".zig-cache"
    "zig-cache"
    "zig-out"
    "zig-pkg"
    "result"
    "devenv.local.nix"
  ];

  keepSource = path: type:
    let base = baseNameOf (toString path);
    in lib.cleanSourceFilter path type
       && !(lib.elem base dropped)
       && !(lib.hasPrefix "zig-cache-" base)
       && !(lib.hasPrefix "result-" base);
in
stdenv.mkDerivation {
  pname = "fast_float";
  inherit version;

  src = lib.cleanSourceWith {
    src = ./.;
    name = "fast_float-${version}";
    filter = keepSource;
  };

  strictDeps = true;

  # Zig links and archives with its own tools, and the build graph names no
  # external binutils, so none is pulled in here.
  nativeBuildInputs = [ zig ] ++ extraNativeBuildInputs;

  # The Zig setup hook's default build phase would run `zig build` once with
  # hook-supplied flags; this derivation installs exactly one variant, from the
  # install phase below. `dontInstall` is deliberately NOT set: it would disable
  # the real installPhase. The check phase is switched off too, so the hook
  # cannot add a `zig build test` with flags of its own.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;

  # Defining `installPhase` here is what keeps the hook's own install function
  # from ever being installed, so `-Dlinkage` cannot be dropped by a default.
  installPhase = ''
    runHook preInstall

    # Caches belong under the Nix-provided TMPDIR, outside the unpacked source
    # tree, which is read-only in the sandbox.
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"

    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Dcpu=baseline \
      -Doptimize=ReleaseSafe \
      -Dlinkage=${linkage}

    runHook postInstall
  '';

  # The archive, the bridge header, the upstream header tree, the pkg-config
  # file and the whole licence set are installed by the build graph. One writer
  # per path: a copy here would overwrite a relocatable `prefix` with a fixed
  # one and would be the copy that survives.

  # No checkPhase: `zig build test` reaches the corpus by a build-root-relative
  # path a derivation does not control. Receipts live with whoever ran the gate.

  passthru = {
    linkage = linkage;
    inherit keepSource;
  };

  meta = {
    description = "fast_float ${version}, upstream's header-only C++11 correctly-rounded decimal-to-binary parser, built to a ${if linkage == "dynamic" then "shared" else "static"} C ABI library with a Zig facade";
    homepage = "https://github.com/fastfloat/fast_float";
    license = "Apache-2.0 OR MIT OR BSL-1.0";
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };
}