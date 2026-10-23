{
  description = "fast_float — upstream's header-only C++11 correctly-rounded decimal-to-binary parser, built to a real C ABI library and wrapped in Zig";

  # flake.lock pins the nixpkgs revision named above.
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

      # Use the Zig release required by build.zig.zon.
      fastFloat = pkgs: linkage:
        pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; inherit linkage; };
    in
    {
      packages = forAllSystems (pkgs: rec {
        static = fastFloat pkgs "static";
        shared = fastFloat pkgs "dynamic";

        default = static;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_16
            pkgs.pkg-config
          ];

          # Set the local cache default only when the caller has not provided one.
          shellHook = ''
            if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] && [ -n "''${XDG_CACHE_HOME:-}" ]; then
              export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/fast_float/zig-local"
            fi
          '';
        };
      });
    };
}