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
  version = "8.3.0";

  # Keep test fixtures; the test step reads them at runtime.
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

  nativeBuildInputs = [ zig ] ++ extraNativeBuildInputs;

  # Disable hook phases; the install phase below selects the requested linkage.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # The Nix source is read-only; keep Zig caches under TMPDIR.
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

  # The build graph owns installed outputs; copying them here would break relocatable metadata.


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