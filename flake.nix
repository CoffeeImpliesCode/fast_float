{
  description = "fast_float — upstream's header-only C++11 correctly-rounded decimal-to-binary parser, built to a real C ABI library and wrapped in Zig";

  # One fixed nixpkgs input, and the lock that resolves it. `flake.lock` is
  # committed beside this file and pins exactly the revision below together with
  # its `narHash`, so a flake checked out anywhere — including a copy this
  # package's `build.zig.zon` `.paths` carries to a dependent — resolves this
  # nixpkgs rather than whatever the machine happens to have. `devenv.lock` is
  # not in this tree and is not named; `devenv.yaml` states what it must pin
  # when it is created.
  inputs.nixpkgs.url =
    "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # `zig_0_16` is named rather than aliased: `pkgs.zig` is a moving alias and
      # this SDK is pinned to 0.16.0, which build.zig.zon also states as its
      # `minimum_zig_version`. `linkage` is the only difference between the two
      # packages: one derivation, one source tree, one C ABI.
      fastFloat = pkgs: linkage:
        pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; inherit linkage; };
    in
    {
      packages = forAllSystems (pkgs: rec {
        static = fastFloat pkgs "static";
        shared = fastFloat pkgs "dynamic";

        # This SDK's native policy is a static archive; the default preserves it.
        default = static;
      });

      # Portability parity only; devenv is the canonical environment. Tools only:
      # a shell that had to build the package to exist would make every shell
      # entry a native build.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_16
            pkgs.pkg-config
          ];

          # A default only, and only when the caller supplied neither the Zig
          # cache location nor a scratch root to derive it from.
          shellHook = ''
            if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] && [ -n "''${XDG_CACHE_HOME:-}" ]; then
              export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/fast_float/zig-local"
            fi
          '';
        };
      });
    };
}