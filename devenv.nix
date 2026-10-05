# Canonical development environment for the fast_float Zig SDK.
#
# Tools and tasks only. `outputs` below are lazy, so entering the shell does not
# build anything: `devenv build outputs.static` (or `outputs.shared`) is the
# packaging route, and `zig build` is the local one.
#
# Every task that reads this repository's own files changes into this
# repository's directory first, from a path this file evaluates. It does not
# use `$DEVENV_ROOT`: `devenv --from path:<this SDK>` gives the generated
# wrapper the *project* directory as its cwd, and no caller flag changes that.
#
# Only `sdk:install` chooses a prefix, and that is read out of this repository's
# own step graph rather than assumed. `test`, `smoke` and `check` reach only
# their own compile and run steps: the install step depends on the smoke
# executable, not the other way round (`build.zig:204`), `smoke` depends on the
# run step alone (`build.zig:212`), `test` on the run step alone
# (`build.zig:245`), `check` on `graph.addTargetCheck` alone
# (`build.zig:247-257`), and none of `addTests`, `addSmoke` or `addTargetCheck`
# attaches anything to `getInstallStep()`. The consumer's `run` depends on its
# executable alone (`consumer/build.zig`). So no other task here reaches an
# install step, writes no delivery output, and needs no flag to avoid writing
# one.
#
# Each of the five `zig build` bodies below names its own flags before `"$@"`:
# `-j8`, `--summary all`, and `--cache-dir "$ZIG_LOCAL_CACHE_DIR"` against the
# cache the body's own preamble just resolved. The placement is the point --
# `"$@"` is still last, so a caller who passes `-jN`, `--summary` or a
# `--cache-dir` of their own still decides: the pinned 0.16.0 build runner
# reads the last `-j` on the command line and each occurrence overwrites the
# one before it (`lib/compiler/build_runner.zig:422-427`), and the same is true
# of the summary and cache arguments. The steps, the single `--prefix` and the
# `"$@"` forwarding are otherwise unchanged.
{ pkgs, ... }:

let
  # Named rather than left to callPackage, which would fill it from the moving
  # `pkgs.zig` alias instead of the pinned compiler.
  zig = pkgs.zig_0_16;

  # One derivation per linkage, called exactly as the flake calls it.
  mk = linkage: pkgs.callPackage ./package.nix { inherit zig linkage; };

  # This module's own directory, rendered once as one shell word. Every
  # canonical exec below changes into it before it runs anything.
  #
  # It cannot be `$DEVENV_ROOT`: `devenv --from path:<this SDK>` enters the
  # shell with the *project* directory as the cwd, and `DEVENV_ROOT` names that
  # project. That directory holds no `build.zig`, no `UPSTREAM.sha256` and no
  # `consumer/`, so a task that trusted it searched for this SDK's inputs
  # where this SDK is not. `./.` is the directory of the file that writes it,
  # so it is this SDK by construction and not by where the caller stood.
  #
  # `builtins.toString` turns the path into a string instead of leaving a path
  # value inside the generated wrapper, and `lib.escapeShellArg` is this
  # workspace's quoting convention (`htscodecs/package.nix` uses the same
  # function). Whether Nix renders that string as this working tree or as a
  # store copy of it is a property of how a path literal stringifies, not of
  # this expression; no run has observed which it was, and either rendering
  # contains the `build.zig`, `UPSTREAM.sha256` and `consumer/` these tasks
  # read.
  sdkRoot = pkgs.lib.escapeShellArg (builtins.toString ./.);
  consumerRoot = pkgs.lib.escapeShellArg (builtins.toString ./. + "/consumer");

  # Both Zig cache directories, resolved inside the body of every task that
  # starts a compiler and before that compiler runs. `devenv tasks run --mode
  # single <name>` executes a task body without the `enterShell` hook, so a
  # default that lives only in `enterShell` is skipped by exactly the
  # invocation a canonical gate uses; with neither variable set the build
  # would create `.zig-cache` inside this tree. Each variable is filled only
  # when it is unset, so a caller that exported one keeps it, and the order is
  # `XDG_CACHE_HOME`, then `$TMPDIR`, then a refusal.
  #
  # The four names are this SDK's own: `zig-global` and `zig-local` beneath
  # `XDG_CACHE_HOME` (`enterShell` below) and `zig-global-cache` and
  # `zig-local-cache` beneath `$TMPDIR` (`package.nix:83-84`, and this SDK's
  # own `sdk:install` fallback, which now reads the value this fills). No new
  # variable is introduced: these are the two Zig itself reads.
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

  # Bound out here on purpose: `default` refers to this binding, not to
  # `config.outputs.static`. An attribute cannot read the module configuration
  # that is still being defined by the very attribute set that contains it -
  # that is the infinite recursion. The binding is a plain thunk over
  # callPackage, so naming it realises nothing.
  fastFloatStatic = mk "static";
in
{
  packages = [
    zig
    pkgs.pkg-config
  ];

  # Exactly the same derivation and the same options the flake uses.
  outputs = {
    static = fastFloatStatic;
    shared = mk "dynamic";
    # This SDK's linkage policy is static, so `default` follows it.
    default = fastFloatStatic;
  };

  enterShell = ''
    # Defaults only. A caller that already supplied a scratch root, an
    # XDG_CACHE_HOME or a Zig cache location keeps it; this never unsets one.
    # This hook is the shell-session half of the rule; `cacheDirs` is the half
    # that reaches a task, because `devenv tasks run --mode single <name>`
    # executes a task body without running this hook at all.
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
      # The installed tree is a delivery artefact, and a delivery artefact does
      # not belong in the working copy or on the mount that holds it. The
      # default prefix therefore sits beneath the Zig local cache resolved
      # above, and `PREFIX=` overrides it outright. `$TMPDIR/zig-local-cache`
      # is still the name beneath `TMPDIR` -- the one `package.nix` uses and the
      # one `cacheDirs` fills above -- and a caller that exported no cache and
      # named no XDG directory and no `TMPDIR` is stopped by that preamble
      # rather than quietly handed a `zig-out/` inside the repository. `-j8
      # --summary all` and the explicit `--cache-dir` sit before `"$@"`, which
      # still reaches the compiler unchanged.
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