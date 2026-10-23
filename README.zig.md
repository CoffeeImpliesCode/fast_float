# Zig facade API

## Typed parsing

The facade parses `float` and `double` values in upstream's general format.

| Declaration | Result |
|---|---|
| `parse32(bytes: []const u8) Error!Parsed32` | Longest leading number as `f32`. |
| `parse64(bytes: []const u8) Error!Parsed64` | Longest leading number as `f64`. |
| `parse32Exact(bytes: []const u8) Error!f32` | `f32` only when the number fills the buffer. |
| `parse64Exact(bytes: []const u8) Error!f64` | `f64` only when the number fills the buffer. |

`Parsed32` contains `value: f32` and `consumed: usize`. `Parsed64` contains `value: f64` and `consumed: usize`. `consumed` counts input bytes in the parsed prefix. The input slice is borrowed for the call and is not retained. The facade does not allocate.

The parser accepts fixed or scientific notation. It rejects leading whitespace and `+`. It accepts negative values, infinity, and NaN. It rounds to nearest, ties to even, and produces subnormal values.

## Errors

| Error | Meaning |
|---|---|
| `InvalidArgument` | Status 1: no valid number matched, or an exact parse left trailing bytes. |
| `ResultOutOfRange` | Status 2: the number rounded to infinity or zero. The typed call returns no value. |
| `StatusNotRecognised` | The bridge returned an unknown status. |

An exact parse that rejects a trailing suffix has no bridge error behind it. The prefix parse succeeded, then the facade compared `consumed` with the buffer length.

## Raw C interface

`pub const c` exposes the complete translated bridge header:

```c
enum ff_status { FF_STATUS_OK = 0, FF_STATUS_INVALID_ARGUMENT = 1,
                 FF_STATUS_RESULT_OUT_OF_RANGE = 2 };
int ff_parse_f32(const char *first, const char *last, float *out_value, size_t *out_consumed);
int ff_parse_f64(const char *first, const char *last, double *out_value, size_t *out_consumed);
```

The input range is half-open. Its pointers must refer to one live allocation, and an empty range is valid. Both output pointers must be non-null and writable.

| Status | `out_value` | `out_consumed` |
|---|---|---|
| `FF_STATUS_OK` (0) | written | written |
| `FF_STATUS_RESULT_OUT_OF_RANGE` (2) | written with infinity or zero | written |
| `FF_STATUS_INVALID_ARGUMENT` (1) | unchanged | unchanged |

Use the raw interface to inspect the rounded value and consumed count on an out-of-range result. Typed calls discard both outputs on errors.

## Runtime loader API

`runtime_loaded` is a compile-time `bool`. `LoadSource` is `.path` for an absolute file path or `.system` for a name searched by the platform loader. `load(source: LoadSource) LoadError!void` opens the explicit provider and keeps it loaded until process exit. The request must be valid and the provider must export both bridge functions.

The first successful request selects the provider. An identical request succeeds again. A different request returns `error.ProviderMismatch`. Loader failures return `LoadError`. Calling `load` in a linked build panics.

`loadedSource() ?LoadSource` returns the retained request, or `null` before loading and in linked builds. The returned request is owned by the loader and remains valid for the process.

`LoadError` includes `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, and `ReentrantLoad`.
