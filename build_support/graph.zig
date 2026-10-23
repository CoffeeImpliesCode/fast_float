//! How one target's fast_float graph is assembled, and what an install of it
//! contains.
//!
//! `build.zig` decides which steps exist and reads which options. Everything
//! that turns a (target, optimize, linkage) triple into compiled artifacts, and
//! everything `zig build install` publishes about them, lives here, so the
//! native graph, the six cross-target checks and the install layout are built
//! by one list of sources and one list of flags rather than by copies of them.
//!
//! The library is header-only C++11+. Upstream's own CMakeLists defines an
//! INTERFACE target and installs `include/fast_float`; there is nothing to
//! compile from upstream's tree. The one thing a header-only library can
//! usefully do from a package build is compile its real headers into a library
//! that has external linkage, so this file builds a C ABI bridge over
//! `include/fast_float/*.h`, translates the bridge's C header for Zig, and
//! hands both to a facade module.
//!
//! There is deliberately no `b.systemIntegrationOption`. A header-only library
//! installs no binary, so a "system" fast_float is a directory of headers with
//! no installed ABI to bind to and nothing for a system mode to select; adding
//! the option would advertise a mode that cannot be honoured. The rule is
//! vacuous here, not satisfied. See UPSTREAM.md, "System-library mode".
//!
//! Static and shared delivery
//! -------------------------
//! `-Dlinkage` selects the artifact and nothing else. The default is `static`,
//! which is what this package produced before the option existed: the same
//! translation unit, the same upstream headers, the same `-std=c++17`, the same
//! facade, the same tests and the same example. `dynamic` links the same object
//! into a shared object, and takes three things the static archive does not:
//!
//!   * **Position independence.** `.pic = true` on the artifact's own module.
//!     There is exactly one C++ translation unit in this package and it is
//!     compiled on that module, so nothing here is an independently compiled
//!     object that could be left non-PIC behind a shared artifact.
//!   * **An export surface that is exactly the bridge.** `zig/bridge.h`
//!     decorates nothing: its two declarations are plain `extern "C"`, because
//!     one header has to serve the archive, the DLL and a consumer that
//!     includes it directly. So `-fvisibility=hidden` cannot be used -- it would
//!     hide the two entry points too, since nothing widens them back. Instead
//!     the export surface is stated at link time, where it can be exact without
//!     touching the header: a generated linker version script with a `local: *`
//!     arm on ELF targets, and a generated Windows module definition on COFF,
//!     where a DLL exports nothing at all unless something tells it to. The
//!     `local: *` arm matters more here than for a C library: this artifact's
//!     link closure carries a C++ runtime, and every symbol of it would
//!     otherwise land in the shared object's dynamic symbol table and
//!     interpose on another copy of that runtime in the same process.
//!   * **A soname.** Upstream installs no library, so it has no ABI to
//!     version and this is the fork's own number for the C ABI `zig/bridge.h`
//!     declares; see `abi_version`.
//!
//! Darwin gets no export list. That is a platform boundary this build states
//! rather than papers over: `ld64` exports every global symbol by default, and
//! this build has no first-class way to narrow it, so a macOS shared object
//! carries a wider export table than the ELF one. The C ABI a consumer calls
//! is identical on both.
//!
//! ## A target that cannot carry the requested artifact is refused
//!
//! One target in this package's own six is in that position: `wasm32-wasi` has
//! no dynamic linker -- `std.Target.DynamicLinker.kind` is `.none` for it
//! (`lib/std/Target.zig:2385`) -- so a `.so` there would be a file nothing can
//! load. `-Dlinkage=dynamic` is therefore **refused** for it, not downgraded:
//! `sharedObjectRefusal` returns the reason, `build` turns it into a configure
//! failure for the selected target, and `addTargetCheck` turns it into a
//! failing step for that matrix cell. A caller who asked for a shared object
//! gets an error naming the target, not an archive they did not ask for behind
//! a line of output that said so.
//!
//! The default is unaffected and stays distinct from all of this: no
//! `-Dlinkage` at all means `static`, and a static archive is exactly what
//! `wasm32-wasi` takes. `zig build check` with no `-Dlinkage` therefore still
//! compiles all six matrix cells, WASI included.
//!
//! One target looks like that boundary and is not. `std.Target.DynamicLinker.kind`
//! answers `.none` for `.windows` as well (`lib/std/Target.zig:2380`), because a
//! PE/COFF image has no interpreter path and its imports are resolved by the
//! loader inside the OS -- but a Windows target carries a shared object
//! perfectly well, as `fast_float.dll` and its import library, so `-Dlinkage=dynamic`
//! is delivered there, not refused. `targetCarriesSharedObject` names that
//! exception explicitly rather than letting the std function answer for it.
//!
//! Installed closure
//! -----------------
//! `zig build` installs, and this file owns every path in the list:
//!
//!   * the native artifact -- `libfast_float.a`, or `libfast_float.so.0.1.0`
//!     with `libfast_float.so.0` and `libfast_float.so` beside it -- and, on
//!     Windows, `fast_float.dll` in `bin/` with its import library
//!     `fast_float.lib` in `lib/`;
//!   * the whole upstream public header tree under `include/fast_float/` and
//!     `fast_float_bridge.h` beside it, attached to the artifact so they are
//!     also on the include path of anything that links it;
//!   * `lib/pkgconfig/fast_float.pc`, relocatable through `${pcfiledir}`;
//!   * `share/licenses/fast_float/` with every carried licence and provenance
//!     record, including the known-answer corpus's own copy of the Apache-2.0
//!     text under a distinct name.
//!
//! The 262 MB known-answer corpus itself is *not* installed. It is test input
//! that `zig build test` reads from the source tree by a path relative to the
//! build root, and no runtime consumer reads it.

const std = @import("std");

/// The runtime-loading half, owned by the API role: the generated dispatch
/// builder, and the loader-core module a linked build imports for its two
/// public types. Only `addGraph` below calls into it, so the two configurations
/// cannot both create a core instance.
const runtime_graph = @import("../runtime/graph.zig");

/// Upstream's public C++ header tree. These nine headers under
/// `include/fast_float/` are the whole of upstream's library; the bridge below
/// compiles them into the artifact this package installs.
pub const upstream_include = "include";

/// The fork's C ABI bridge. `zig/bridge.h` is plain C, is the root source file
/// of the translate-c run, and is the header a C consumer includes. Its own
/// directory is on the translation line because `zig/` is not a system include
/// directory.
pub const bridge_header = "zig/bridge.h";

/// The only C++ translation unit in the package.
pub const bridge_source = "zig/bridge.cpp";

/// The name the bridge header is installed under. `bridge.h` is too generic to
/// publish next to the nine upstream headers, and this is the name a C consumer
/// will `#include`, so it is fixed here once.
pub const bridge_header_install_name = "fast_float_bridge.h";

/// The artifact name. It is also the package name and the public module name,
/// so `zig-out/lib/libfast_float.a`, `@import("fast_float")` and
/// `#include <fast_float_bridge.h>` all name the same thing from three sides.
pub const artifact_name = "fast_float";

pub const facade_root = "zig/root.zig";
pub const tests_root = "tests.zig";
pub const smoke_root = "smoke.zig";

/// The independent known-answer corpus, read from disk at test run time rather
/// than embedded. The corpus is 262 MB across thirteen files; embedding it
/// would put those bytes in the test object once per optimize mode and once
/// per cross target, for a fixture that is read sequentially once.
pub const fixture_data_dir = "testdata/supplemental/data";

/// The module name the test root imports to find that corpus.
pub const fixture_module_name = "fast_float_paths";

/// Compile flags for the bridge.
///
/// `-std=c++17` is a pin, not a preference. Upstream sets
/// `FASTFLOAT_CXX_STANDARD` to 11 and asks for `cxx_std_11`, so C++17 is a
/// strict superset of what upstream asks for and is inside the range upstream's
/// own CI exercises; it is also below the two thresholds that would change how
/// upstream's headers compile themselves, so pinning it here cannot silently
/// select a different algorithm:
///
///   * `include/fast_float/float_common.h:13` includes `<stdfloat>` only when
///     `__cplusplus > 202002L`, so the C++20 float type is off.
///   * `include/fast_float/constexpr_feature_detect.h:17` turns on
///     `FASTFLOAT_HAS_BIT_CAST` only for `__cpp_lib_bit_cast >= 201806L`, which
///     is a C++20 library feature, so `<bit>` stays out.
///
/// Leaving the standard to the compiler default would make the build depend on
/// which clang Zig ships, and a future default bump to C++20 would switch
/// upstream's code paths with no change in this repository.
///
/// Nothing here varies with `-Dlinkage`. Both deliveries compile the one C++
/// translation unit with exactly these flags; the difference is how the object
/// is linked and which symbols the link exports.
pub const bridge_flags = [_][]const u8{
    "-std=c++17",
};

/// Upstream's own version, read out of `include/fast_float/float_common.h:19-21`
/// (`FASTFLOAT_VERSION_MAJOR` 8, `FASTFLOAT_VERSION_MINOR` 3,
/// `FASTFLOAT_VERSION_PATCH` 0) and out of `CMakeLists.txt:4`
/// (`project(fast_float VERSION 8.3.0)`).
///
/// It is the version the installed `fast_float.pc` states and the version
/// `build.zig` refuses to configure against a `build.zig.zon .version` that
/// disagrees, so the manifest, the pkg-config record and the upstream headers
/// cannot describe three different releases.
pub const upstream_version: std.SemanticVersion = .{ .major = 8, .minor = 3, .patch = 0 };

/// The shared object's version, and therefore its soname
/// `libfast_float.so.0`.
///
/// This is *not* an upstream number: upstream installs no library at all -- its
/// CMake target is `INTERFACE` (`CMakeLists.txt:33`) and its install rules copy
/// headers and a CMake package config -- so there is no upstream ABI to version
/// a compatibility tag against. This one is the fork's own, and it describes
/// the C ABI `zig/bridge.h` declares: two functions, each returning an
/// `int` status and writing a value and a byte count into caller-owned
/// pointers. Bumping `major` means an incompatible change to that header, and
/// nothing else; a new upstream release does not move it, and neither does a
/// new typed method in `zig/root.zig`.
///
/// `std.SemanticVersion` has three components where a Linux shared object's
/// name has four, so the file is `libfast_float.so.0.1.0`. The soname -- the
/// number a consumer's `DT_NEEDED` records, and the basename a `.system` load
/// has to name -- is `libfast_float.so.0`.
pub const abi_version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

/// The complete externally linked ABI of the fork bridge.
///
/// One entry per definition in `zig/bridge.cpp`, which is one per declaration
/// in `zig/bridge.h`: `ff_parse_f32` (`:103-104`) and `ff_parse_f64`
/// (`:112-113`). There is no data symbol, no target- or configuration-dependent
/// entry, and no inline body to exclude, so this list is the whole of it.
///
/// It exists for the two export surfaces that cannot be taken from the header:
/// `addVersionScript` and `addWindowsExports`. Keep it in step with the bridge
/// header: a name added there and not here builds and passes every ELF gate and
/// is simply missing from the shared object's export table.
pub const bridge_abi_symbols = [_][]const u8{
    "ff_parse_f32",
    "ff_parse_f64",
};

/// Targets whose shared objects take a GNU ld version script.
///
/// The set is the one `inchi/build.zig:320-333` uses for the same two
/// decisions, because it is the same fact twice: ELF-unix is where `--version-
/// script` is understood at all, and it is also where `libm` is a separate
/// library. Nothing else in this file depends on it.
const elf_unix_tags = [_]std.Target.Os.Tag{
    .linux,
    .freebsd,
    .netbsd,
    .openbsd,
    .dragonfly,
    .illumos,
};

fn isElfUnix(target: std.Build.ResolvedTarget) bool {
    for (elf_unix_tags) |tag| {
        if (target.result.os.tag == tag) return true;
    }
    return false;
}

/// The cross-target compile matrix. Every entry must compile the C++ bridge,
/// the translated bridge header, the facade, the behavioural tests and the
/// smoke example. Nothing here is skipped and nothing here is pre-judged: if a
/// target cannot be built, the compile is attempted and reports why.
pub const required_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Whether this target can carry a shared object at all.
///
/// For most targets that is exactly the question `std.Target.DynamicLinker.kind`
/// answers from the OS tag alone (`lib/std/Target.zig:2345-2402`): the
/// `arch_os` and `arch_os_abi` families have a dynamic linker, `.none` does
/// not, and WASI is `.none` (`:2385`) while this package's own matrix walks it.
///
/// Windows is the one exception, and it is not a small one: `.windows` is
/// `.none` there too (`lib/std/Target.zig:2380`) because a PE/COFF image has
/// no interpreter path at all -- its imports are resolved by the loader inside
/// the OS -- yet a Windows target carries a shared object perfectly well, as
/// `fast_float.dll` plus the import library `fast_float.lib`. Treating that
/// `.none` as "no shared object" would refuse `-Dlinkage=dynamic` on every
/// `windows-gnu` cell of the matrix and leave `addWindowsExports` unused, so
/// the two families are named separately here.
///
/// One consequence is stated rather than solved here: a *linked* executable on
/// Windows needs the DLL beside it or on `PATH`, which is the ordinary Windows
/// rule for a shared library and not something the build graph can arrange for
/// an arbitrary consumer's output directory.
pub fn targetCarriesSharedObject(target: std.Build.ResolvedTarget) bool {
    if (target.result.os.tag == .windows) return true;
    return std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Why a requested shared object cannot be delivered for one target, or `null`
/// when it can.
///
/// A refusal, not a substitution. There is no third answer: this build either
/// delivers the artifact the caller named or it fails saying which target
/// refused it and why, and it never answers a request for a shared object with
/// an archive.
pub fn sharedObjectRefusal(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) ?[]const u8 {
    if (targetCarriesSharedObject(target)) return null;
    return b.fmt(
        "-Dlinkage=dynamic was requested and {s} cannot carry a shared object: " ++
            "its OS has no dynamic linker (std.Target.DynamicLinker.kind is " ++
            ".none), so a {s} there is a file nothing can load. Nothing was " ++
            "substituted. Build this target with -Dlinkage=static, which is the " ++
            "default, or name a target whose platform has a loader.",
        .{
            @tagName(target.result.os.tag),
            if (target.result.os.tag == .wasi) ".wasm shared library" else "shared object",
        },
    );
}

/// One target's compiled artifacts.
pub const Graph = struct {
    /// The C ABI artifact a C or C++ consumer links. It is built and installed
    /// in both configurations: under `-Druntime` it is what a provider *is*,
    /// not something the module links.
    bridge: *std.Build.Step.Compile,
    /// The Zig facade. Its `c` import is the translated bridge header in a
    /// linked build and the generated runtime dispatch in a runtime-loading one.
    module: *std.Build.Module,
};

/// Builds the C ABI bridge, translates the bridge header, and builds the
/// facade module over both.
///
/// `linkage` is the delivery this graph delivers; `name` is the artifact name
/// this graph reports, which is the package name for the published graph and a
/// target-decorated name for a cross-target check (six graphs in one build
/// otherwise produce six steps called `fast_float`).
///
/// `public` selects between the package module set, which is what a dependent
/// reaches through `dep.module("fast_float")`, and a private module. A cross
/// target check needs the private form: modules are registered by name against
/// the whole build, so registering `fast_float` once per cross target would
/// leave only the last of them reachable and silently stop checking the rest.
///
/// ## The runtime-loading seam
///
/// `runtime/graph.zig`, which the API role owns, exposes
///
///     pub fn createModule(b: *std.Build, translate: *std.Build.Step.TranslateC,
///         target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module
///
/// and `-Druntime` substitutes that one call for the translated module. It is
/// handed the very `translate_c` step built below, so the generated dispatch
/// keeps the exact translated constant namespace rather than compiling a second
/// copy of it: `zig/root.zig`'s `c.FF_STATUS_OK` and the declaration behind the
/// table are one value with one spelling.
///
/// Two things are deliberately *not* done in that branch. The archive is not
/// linked into the module -- linking it would make the linker resolve the same
/// symbols statically and the runtime route would quietly be a linked one --
/// and the core module is not created here a second time, because `createModule`
/// makes the one instance the dispatch re-exports `LoadSource`/`LoadError`
/// from. Two instances would be two nominally distinct `LoadSource`, and
/// `fast_float.load(source)` would hand the facade's type to a function
/// expecting the dispatch's.
///
/// The artifact itself is still built and installed either way: delivery and
/// dispatch are separate questions, and the point of the mode is that a caller
/// may name a provider this tree did not build *or* the one it did.
///
/// `-Dlinkage` is orthogonal and keeps meaning what it means throughout.
pub fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: std.lang.LinkMode,
    name: []const u8,
    public: bool,
    runtime_loaded: bool,
) Graph {
    const bridge_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // `<cstring>`, `<cstdlib>` and `<system_error>` come in through
        // upstream's headers.
        .link_libc = true,
        // A real C++ translation unit, so the artifact has C++ linkage
        // requirements and must say so. Setting it once here is enough for
        // every consumer: `Module.linkLibrary` records the bridge in the
        // dependee's module graph (std/Build/Module.zig:649-659), and the
        // driver walks that graph transitively, including through linked
        // libraries, before emitting `-lc++` (std/Build/Step/Compile.zig:
        // 1053-1058 and 1351-1353). A test or example that links this facade
        // therefore gets libc++ without repeating the flag, and a dependent
        // package gets it the same way. For the shared delivery it also means
        // the C++ runtime is part of the image rather than a `-lc++` a consumer
        // has to find, which is what `addPkgConfig` below records.
        .link_libcpp = true,
        // A shared object has to be position independent or the loader cannot
        // place it away from its link address. `null` is the compiler's own
        // choice, which is what the static delivery has always built; making it
        // explicit for `dynamic` puts the requirement on the same module that
        // compiles the bridge rather than leaving it to the link step.
        .pic = if (linkage == .dynamic) true else null,
    });
    // The upstream headers have to be on the library's own compile line, not
    // only on the include tree that `installHeadersDirectory` publishes.
    bridge_mod.addIncludePath(b.path(upstream_include));
    bridge_mod.addCSourceFiles(.{
        .files = &.{bridge_source},
        .flags = &bridge_flags,
    });

    const bridge = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        // `null` for the static archive, which has no soname and no versioned
        // file name; `abi_version` for the shared object.
        .version = if (linkage == .dynamic) abi_version else null,
        // A COFF/PE DLL exports nothing unless something says otherwise, and
        // the bridge declarations carry no `__declspec(dllexport)` on purpose:
        // that is what lets one header serve the archive, the DLL and a
        // consumer that includes it directly. `Step.Compile` reads this only
        // for a library, a `.dynamic` linkage and a COFF target
        // (std/Build/Step/Compile.zig:479-485), so the file is generated for
        // exactly that combination.
        //
        // There is no declaration-side half to this split, and there does not
        // need to be: `__declspec(dllimport)` is required for *data* imported
        // from another module and merely saves an indirection for *functions*,
        // and this ABI exports functions only. A consumer therefore gets the
        // import-library thunk the linker emits, with no macro of its own and
        // nothing in the installed `Cflags` that would be false for the
        // archive.
        .win32_module_definition = if (linkage == .dynamic and target.result.ofmt == .coff)
            addWindowsExports(b)
        else
            null,
        .root_module = bridge_mod,
    });

    if (linkage == .dynamic and isElfUnix(target)) {
        // The export surface, stated at link time because the header states
        // nothing: the anonymous version tag below assigns no version to any
        // symbol, so `ff_parse_f32` stays unversioned and `local: *` only
        // decides what the dynamic symbol table may contain.
        bridge.setVersionScript(addVersionScript(b));
    }

    // The whole upstream public header tree goes in beside the bridge, because
    // upstream installs `include/fast_float` wholesale (CMakeLists.txt:78) and a
    // C++ consumer of this package must keep getting `#include
    // <fast_float/fast_float.h>`. The `.h` filter installs all nine of them and
    // omits nothing: `include/fast_float` contains nine headers and no other
    // file. Attaching both to the artifact also puts them on the include search
    // path of anything that links it (std/Build/Step/Compile.zig:520-522), so
    // a dependent reaches the headers without reaching into this repository's
    // tree.
    bridge.installHeadersDirectory(
        b.path(upstream_include),
        "",
        .{ .include_extensions = &.{".h"} },
    );
    bridge.installHeader(b.path(bridge_header), bridge_header_install_name);

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path(bridge_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("zig"));

    const c_module = if (runtime_loaded)
        // The generated dispatch. It imports the translation itself as
        // `c_native`, so nothing here needs the translated module as a second
        // copy and `dep.module("c")` is deliberately not registered: this
        // branch owns the name `c` inside the facade.
        runtime_graph.createModule(b, translate_c, target, optimize)
    else if (public)
        translate_c.addModule("c")
    else
        translate_c.createModule();

    const module = if (public)
        b.addModule(artifact_name, .{
            .root_source_file = b.path(facade_root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    module.addImport("c", c_module);
    if (!runtime_loaded) {
        // `rt` carries the two public types a linked build has no dispatch for.
        // A runtime-loading build must not add it: the dispatch re-exports both
        // from the one core instance `createModule` made.
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));
        module.linkLibrary(bridge);
    }

    return .{ .bridge = bridge, .module = module };
}

/// Writes the ELF export list: the two bridge entry points and nothing else.
///
/// The anonymous `{ ... }` tag is deliberate and is the form upstream InChI's
/// own `libinchi.map` uses: an anonymous version tag assigns no symbol version,
/// so a `nm -D` of the result reads `ff_parse_f32` rather than
/// `ff_parse_f32@@SOMETHING`, and the declaration in `zig/bridge.h` stays
/// literally true of the library a consumer links.
fn addVersionScript(b: *std.Build) std.Build.LazyPath {
    return b.addWriteFiles().add("fast_float.map", b.fmt(
        \\{{
        \\global:
        \\    {s};
        \\    {s};
        \\local:
        \\    *;
        \\}};
        \\
    , .{ bridge_abi_symbols[0], bridge_abi_symbols[1] }));
}

/// Writes the Windows module definition that gives the DLL a real export table.
///
/// One `.def` per shared build, listing exactly the wrappers `zig/bridge.cpp`
/// defines. A `.def` entry for a symbol the artifact does not define is a link
/// error rather than a harmless extra line, which is why the list is generated
/// from the one declaration it has to match rather than appended to by hand.
fn addWindowsExports(b: *std.Build) std.Build.LazyPath {
    // `Step.WriteFile.add` copies the bytes into the build allocator, so this
    // buffer stays owned by that allocator for the rest of the run.
    var out: std.Io.Writer.Allocating = .init(b.allocator);
    out.writer.print("EXPORTS\n", .{}) catch @panic("OOM");
    for (bridge_abi_symbols) |symbol| {
        out.writer.print("{s}\n", .{symbol}) catch @panic("OOM");
    }
    return b.addWriteFiles().add("fast_float.def", out.written());
}

/// Installs `lib/pkgconfig/fast_float.pc`.
///
/// `prefix` is `${pcfiledir}/../..`, not the `--prefix` this build was
/// configured with. pkg-config substitutes `pcfiledir` with the directory it
/// found the file in, so the installed record is right for the prefix actually
/// installed under, including a `--prefix` chosen after configuration, a Nix
/// `$out`, or a tree moved after installation. The derivation writes no `.pc` of
/// its own for the same reason: it used to, with a configured-in absolute
/// prefix, and two records for one artifact is exactly the state in which
/// `pkg-config` answers differently depending on which file it found -- and the
/// one that ran last won.
///
/// The record describes a Unix prefix layout. On Windows-gnu it still describes
/// this tree honestly -- the import library `fast_float.lib` lands in `lib/`
/// and the DLL `fast_float.dll` in `bin/` -- but a mingw consumer names the
/// import library directly, and nothing here claims how a Windows toolchain's
/// own `pkg-config` would resolve `-lfast_float`. That is outside what this
/// build can observe.
///
/// `Libs.private` differs between the two deliveries, and the difference is
/// real rather than cosmetic:
///
///   * `static` names the C++ runtime. The archive is compiled from C++ and
///     carries C++ runtime references, so a consumer linking it statically has
///     to link the runtime too -- this is the same requirement the artifact's
///     own module states with `link_libcpp`, and `inchi/build.zig:884-886`
///     records the same reasoning for its own `Libs.private`.
///   * `dynamic` names nothing: the C++ runtime is linked into the shared
///     object, so there is no `-lc++` left for a consumer to resolve.
///
/// There is no `-lm`. All nine upstream headers were read for this: they
/// include `<cmath>` (`parse_number.h:9`, `decimal_to_binary.h:8`) and call no
/// function from it, and the only C library entry point they reference is
/// `memcpy` (`ascii_number.h:63` and elsewhere), which every consumer already
/// links. Naming a dependency the compiled closure does not have is how a
/// pkg-config record starts lying.
///
/// `Requires:` is empty for the same reason: there is no build-time or
/// link-time dependency outside libc and the C++ runtime, and neither is
/// something pkg-config can express portably.
///
/// The install is attached with `b.installFile`, not
/// `b.addInstallFileWithDir`. The `add…` form only *creates* the
/// `Step.InstallFile`: `Step.InstallFile.create` adds the source's own step
/// dependencies and nothing else (`lib/std/Build/Step/InstallFile.zig:15-36`),
/// and `Build.addInstallFileWithDir` hands that step back without attaching it
/// to anything (`lib/std/Build.zig:1717-1724`). An unattached install step is
/// never made, so the record would be absent from every prefix while
/// `zig build` still exited zero and installed the archive beside it --
/// precisely the failure mode that hides a whole delivery behind one green
/// command. `b.installFile` is the form that adds it to the install step
/// (`lib/std/Build.zig:1675-1677`) and it uses the same `InstallDir.prefix`
/// these paths want.
pub fn addPkgConfig(b: *std.Build, linkage: std.lang.LinkMode) void {
    const libs_private = if (linkage == .static) "\nLibs.private: -lc++" else "";
    const pc = b.addWriteFiles().add("fast_float.pc", b.fmt(
        \\# Generated by this package's build.zig from its own install layout.
        \\# Do not edit; see build_support/graph.zig, addPkgConfig.
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\libdir=${{prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: fast_float
        \\Description: fast_float, correctly-rounded decimal to binary floating point conversion, with this fork's C ABI bridge
        \\URL: https://github.com/fastfloat/fast_float
        \\Version: {f}
        \\
        \\Libs: -L"${{libdir}}" -lfast_float
        \\Cflags: -I"${{includedir}}"{s}
        \\
    , .{ upstream_version, libs_private }));
    const install_pc = b.addInstallFileWithDir(pc, .lib, "pkgconfig/fast_float.pc");
    b.getInstallStep().dependOn(&install_pc.step);
}

/// One carried licence or provenance record, and the name it is installed
/// under.
pub const LicenceRecord = struct {
    /// Where the record is in this repository.
    source: []const u8,
    /// Its name in the installed tree. It differs from `source` in exactly one
    /// case, and the reason is in `licence_records`.
    installed_name: []const u8,
};

/// The licence and provenance material an installed binary form has to carry.
///
/// fast_float is triple licensed and a private downstream removes no upstream
/// obligation, so all three upstream texts ship and `NOTICE.md` says which is
/// which. `FORK-LICENSE.md` records the owner-authorised grant for this fork's
/// own files, `UPSTREAM.md` records the pin and what this fork changed, and
/// `README.upstream.md` is upstream's own README kept byte for byte -- it is
/// where upstream states its three grants (`README.upstream.md:191-197`), so it
/// is a licence record here and not merely documentation.
///
/// `testdata/supplemental/LICENSE` is installed under a distinct name because
/// it is a distinct copy of the Apache-2.0 text: it does not carry upstream's
/// copyright line, so calling it `LICENSE-APACHE` beside the real one would be
/// false.
pub const licence_records = [_]LicenceRecord{
    .{ .source = "LICENSE-APACHE", .installed_name = "LICENSE-APACHE" },
    .{ .source = "LICENSE-MIT", .installed_name = "LICENSE-MIT" },
    .{ .source = "LICENSE-BOOST", .installed_name = "LICENSE-BOOST" },
    .{ .source = "NOTICE.md", .installed_name = "NOTICE.md" },
    .{ .source = "FORK-LICENSE.md", .installed_name = "FORK-LICENSE.md" },
    .{ .source = "UPSTREAM.md", .installed_name = "UPSTREAM.md" },
    .{ .source = "README.upstream.md", .installed_name = "README.upstream.md" },
    .{ .source = "testdata/supplemental/LICENSE", .installed_name = "testdata-supplemental-LICENSE" },
};

/// Installs the carried licence texts and provenance records under
/// `share/licenses/fast_float/`.
///
/// A package that ships a binary without them is the failure this prevents.
///
/// This is the only writer of `share/licenses/<name>/`. `package.nix` installs
/// nothing itself: it used to copy these files itself, which meant two records
/// for one output and a licence set that could disagree with the artifact it
/// sat beside. The build graph owns install paths, so the build graph owns this
/// list.
///
/// The install steps are attached with `b.installFile` for the reason
/// `addPkgConfig` gives: an install step nothing depends on is never made.
pub fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        b.installFile(
            record.source,
            b.fmt("share/licenses/{s}/{s}", .{ artifact_name, record.installed_name }),
        );
    }
}

/// The behavioural test binary for one graph.
///
/// The facade is reachable only through this binary on the cross-target path,
/// which is what makes the check a check of the facade: Zig analyses a
/// function body when something calls it, every public facade method is called
/// from `tests.zig`, and so building this binary for a target analyses all of
/// them for that target.
///
/// It is the same artifact either way: `check` compiles it and stops there,
/// `test` compiles it and hands it to a run step. There is no second, reduced
/// test root for the foreign path, so a target that runs these tests runs the
/// whole corpus at both widths and the same thirteen cases as the host.
pub fn addTests(
    b: *std.Build,
    graph: Graph,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    name: []const u8,
    fixtures: *std.Build.Module,
) *std.Build.Step.Compile {
    const test_mod = b.createModule(.{
        .root_source_file = b.path(tests_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(artifact_name, graph.module);
    test_mod.addImport(fixture_module_name, fixtures);
    return b.addTest(.{ .name = name, .root_module = test_mod });
}

/// Provides the corpus directory to behavioural tests as a build option.
/// The Options step tracks its contents; tests resolve the relative path from the inherited working directory.

pub fn addFixturePaths(b: *std.Build) *std.Build.Module {
    const options = b.addOptions();
    options.addOptionPathDirectory("data_dir", b.path(fixture_data_dir));
    return options.createModule();
}

/// The smoke example for one graph. Compiling it, and running it where the
/// target can run, is the cheapest end-to-end proof that the facade, the
/// translated header and the bridge artifact agree on types and symbols.
pub fn addSmoke(
    b: *std.Build,
    graph: Graph,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    name: []const u8,
) *std.Build.Step.Compile {
    const smoke_mod = b.createModule(.{
        .root_source_file = b.path(smoke_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    smoke_mod.addImport(artifact_name, graph.module);
    return b.addExecutable(.{ .name = name, .root_module = smoke_mod });
}

/// Compiles the C++ bridge, the translated header, the facade, the tests and
/// the example for one target, and attaches both binaries to `parent`.
///
/// Nothing is run. A cross-built binary cannot be executed on the host, so this
/// is compile evidence and never a claim that a foreign binary executed.
///
/// A cell that cannot deliver what the caller asked for becomes a failing step
/// carrying the reason, and nothing is compiled for it. That is the honest
/// result of `zig build check -Dlinkage=dynamic` for `wasm32-wasi`: an
/// explicit refusal for that one cell, with the other five still compiled. The
/// cell is not dropped, not relabelled, and not answered with an archive.
pub fn addTargetCheck(
    b: *std.Build,
    parent: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.lang.Optimize,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
    fixtures: *std.Build.Module,
) void {
    const target = b.resolveTargetQuery(query);
    // Artifact names have to stay unique inside one build graph: the native
    // graph already owns the undecorated names, and six checks in a single
    // invocation would otherwise write six objects to one cache path.
    const label = b.fmt("{s}-{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag) });

    if (linkage == .dynamic) {
        if (sharedObjectRefusal(b, target)) |reason| {
            parent.dependOn(&b.addFail(b.fmt(
                "{s}: {s} No artifact was built for this cell.",
                .{ label, reason },
            )).step);
            return;
        }
    }

    const graph = addGraph(
        b,
        target,
        optimize,
        linkage,
        b.fmt("{s}-{s}", .{ artifact_name, label }),
        false,
        runtime_loaded,
    );

    parent.dependOn(
        &addTests(b, graph, target, optimize, b.fmt("{s}-tests-{s}", .{ artifact_name, label }), fixtures).step,
    );
    parent.dependOn(
        &addSmoke(b, graph, target, optimize, b.fmt("{s}-smoke-{s}", .{ artifact_name, label })).step,
    );
}