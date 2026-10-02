# cross-test settings profile for fast_float.
#
# `cross-test` looks for this file at the root of the project it is run from
# (or names it with --profile; --no-profile ignores it). It is trusted Bash that
# the harness `source`s, so this file is *settings only*: ordinary variable
# assignments and nothing else. No command runs, no compiler is probed, and no
# path in here names a host.
#
# There is deliberately no CROSS_MATRIX. The published 53-platform Zig 0.16
# Tier 1/2 table is the matrix this package is checked against, and a matrix
# named here would replace it. There is no TARGETS array either, for the same
# reason: a subset selected here would narrow the run rather than add to it.
# Both belong on the command line, where --targets selects from the active
# matrix and never adds to it.
#
# CROSS_BUILD_STEP stays the standard `test` step, which is what this profile
# states explicitly. There are no `cross_build_command` / `cross_artifact`
# hooks here, so the harness keeps its standard Zig-build mode and runs
# `zig build test -Dtarget=TARGET` per target with a fresh cache. What that
# means for a given target is the harness's decision, not this package's: a
# host target runs, a foreign target runs under whatever executor the harness
# detects (QEMU user mode, Wine, wasmtime), and a foreign target with no
# executor is reported as build-only coverage -- compiled, never executed, and
# never counted as a pass. `build.zig` gives the test binary a Run step for
# every target, which is what leaves that choice open.
#
# A target graph compiles the C++ bridge and translates its C header alongside
# the facade and test root. Keep four build jobs available.
#
# The corpus case reads all 1,382,483 rows of the nine selected files at both
# widths. The first full matrix compiled all 53 platforms, but this unchanged
# case exceeded the 300-second per-test default on x86_64 and both AArch64
# Linux cells. Allow a bounded longer run; do not sample the corpus or remap
# Debug to an optimized mode. Before-matrix timeout receipts remain history.

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=3600
CROSS_TIMEOUT=1800