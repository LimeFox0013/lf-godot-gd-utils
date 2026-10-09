# Contributing to lf-godot-gd-utils

Issues and pull requests are welcome. Everyone taking part follows the
[Code of Conduct](CODE_OF_CONDUCT.md). To report a vulnerability, do not open an issue:
see [`SECURITY.md`](SECURITY.md).

## Reporting a bug

Open an issue with your Godot version (*Help → About Godot*), the module, a few lines
of GDScript that show the problem, what you expected and what happened instead.

## Changing code

A pull request needs:

- **Tests.** A bug fix starts with a GUT test that fails without the fix. Tests live in
  the module's `tests/` folder.
- **Docs.** The module's `README.md` updated (API table, *Notes*), its row in
  [`LF_INDEX.md`](LF_INDEX.md), and `##` doc comments on every public member.
  `tests/test_lf_index.gd` fails on a class the index doesn't list.
- **Exact claims.** Docs state what the code does, including its limits (platforms,
  scale, performance, security). No claim the code doesn't back.
- **Generic code.** Nothing that knows about one particular game, and no file that names
  the folder lf-godot-gd-utils is installed in.
- **No warnings.** `ci/check_install.sh` loads the release contents with every default
  GDScript warning raised to an error.

Run both checks before opening the pull request:

```
GODOT=/path/to/godot ci/run_tests.sh
GODOT=/path/to/godot ci/check_install.sh
GODOT=/path/to/godot ci/http_smoke.sh   # LFHttp against a local server
```

The scripts are bash and need Python 3 (`python3`, or `python`); `check_install.sh` also
needs `git`. On Windows run them in Git Bash with `GODOT` set to the `..._console.exe`
build (the plain `.exe` does not write to the terminal). Keep them working on Linux, macOS
and Windows: no `rsync`, no GNU-only flags, and a path handed to Python or Godot goes
through `native` from `ci/common.sh`.

Style follows the
[GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html):
`lf_snake_case` files, `LFPascalCase` classes, typed code, past-tense signal names, and
`_ms` at the end of any name that holds milliseconds.

The library is developed with AI coding agents, under review, test-first.

## Versions and deprecation

[`STABILITY.md`](STABILITY.md) is the policy and the per-module *stable* / *experimental*
table. In short: [semantic versioning](https://semver.org/); a breaking change to a stable
module is a major release and is announced first by deprecating the old member in a minor
release and keeping it for at least one more minor release; every user-visible change gets a
[`CHANGELOG.md`](CHANGELOG.md) entry, and a breaking one starts with **Breaking:** and says
what to write instead. A pull request that changes a public member says in its description
which of those it is. A new module is added as *experimental* in `STABILITY.md`.

## Conventions

Rules every module follows. A new member that breaks one needs a reason in its pull
request.

### Injected clocks

Four modules take a clock so that tests and simulations can control time:

| Module | Property | Constructor parameter | Unit | Empty means |
|---|---|---|---|---|
| `LFCooldown` | public `clock_ms` | `initial_clock_ms` | milliseconds | `Time.get_ticks_msec()` |
| `LFLlmToolClient` | public `clock_ms` | `initial_clock_ms` | milliseconds | `Time.get_ticks_msec()` |
| `LFStrikeGuard` | public `clock_seconds` | `initial_clock_seconds` | seconds | `steady_seconds()` |
| `LFAccountStore` | public `clock_unix_seconds` | `initial_clock_unix_seconds` | Unix seconds | `Time.get_unix_time_from_system` |

`LFIntervalTimer`, `LFStatusEffects` and the other simulations take no clock: you pass
`delta` to `tick`.

1. A clock is a `Callable` with no arguments returning the current time as an `int` or a
   `float`. Its unit is in the property's name, as everywhere else: `clock_ms` or
   `clock_seconds` (`clock_unix_seconds` where calendar time is the point, as for an
   expiry written to disk).
2. It is a **public property** with that name, so it can be replaced at any time, and the
   **last optional constructor parameter**, an empty `Callable()` by default. The
   parameter is `initial_<property>` (`initial_clock_ms`), like the library's other
   constructor parameters: a parameter named like a member trips GDScript's shadowing
   warning, which `ci/check_install.sh` turns into an error.
3. An empty clock selects the module's documented default: a steady clock
   (`Time.get_ticks_msec()` or `LFStrikeGuard.steady_seconds()`) unless calendar time is
   needed. The README says which.
4. A clock that cannot be called any more (its object was freed) is reported once through
   `LFLogger` and the module takes its documented safe fallback, as `LFCooldown` and
   `LFLlmToolClient` already do.
5. Constructing never reads the clock.
6. A class that is driven by a frame loop (a simulation) takes `delta` in `tick` instead
   of a clock; it never has both.

### Other rules

- **`clear()` drops everything.** Removing one entry is `forget(key)` or `remove(key)`.
  `reset()` is spelled for what it does: `LFCooldown.reset()` makes it ready, and
  `LFIntervalTimer.restart()` starts the wait over.
- **Argument order.** The object a function works on comes first (`camera` before the
  point it projects); `owner, id, cap` for per-owner caps.
- **A timeout of 0 or less means no deadline**, in every module that takes one. A default
  deadline is what you get by leaving the argument out.
- **NaN is rejected.** A NaN interval, window, delay or time-to-live passed to a
  constructor or setter is reported through `LFLogger` as an error and the value stays as
  it was (the default, at construction).
- **Option dictionaries.** A key the module does not know is reported through `LFLogger`
  naming it, so a misspelt option does not fail silently.
- **An empty `Callable` never means "all".** Removing everything has its own method
  (`clear_event(event)`).
- **Signals** are past-tense or event-style names (`error_occurred`, `output_received`,
  `reconnect_scheduled`), not bare nouns or `-ing` words.
- **Spelling** is American English (`neighbor`).
