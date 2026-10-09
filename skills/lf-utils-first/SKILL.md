---
name: lf-utils-first
description: >
  Reuse before you write. Use this skill in any Godot project that contains a file
  named LF_INDEX.md (the index of the lf-godot-gd-utils GDScript library) BEFORE writing or changing GDScript: a new .gd file, class, function, node script,
  component, helper or utility; timers, tweens, awaits, debounce/throttle, cooldowns;
  signals, event buses, state machines; pooling, ids, indexes, spatial queries, grids,
  flow fields; random rolls, loot, tiers, stats, modifiers, status effects; files, JSON,
  zip, HTTP, WebSocket, processes, threads; cameras, 2D/3D helpers or UI controls. It
  says to look up LF_INDEX.md for an existing class first, and to keep the index complete
  when something is added to LF. Also invocable as /lf-utils-first.
---

# lf-godot-gd-utils — utils first

lf-godot-gd-utils is a library of GDScript helpers, each with GUT tests. Its `LF_INDEX.md` lists every
class: a "Find it by task" table, then one table per group with each class's purpose and
key API. Every module has a README and GUT tests (the library's index test checks this).
Work from the index so you reuse what lf-godot-gd-utils already has instead of writing it again.

## 0. Find the library

Search the project for a file named `LF_INDEX.md` (for example, glob `**/LF_INDEX.md`).
Don't assume a location: lf-godot-gd-utils can be installed in any folder. The folder that holds
`LF_INDEX.md` is the library; below, `<library>` means that folder, wherever it is. If no `LF_INDEX.md` exists, lf-godot-gd-utils isn't installed
and this skill doesn't apply.

## 1. Before writing code: look it up

1. Read `<library>/LF_INDEX.md`: the "Find it by task" table first, then the group table for
   the area you're working in. Do this once per task. In a long session, read it again
   rather than relying on memory.
2. For each candidate, open its module `README.md` (`<library>/src/<group>/lf_<name>/README.md`)
   for the full API and gotchas. The index lists only key members.
3. Use classes by their global `class_name`. Never `preload` them, and never copy their
   code into the project.

If something fits, use it and say which class you reused. If something almost fits,
prefer extending that module (step 3) over writing a near-duplicate beside it.

## 1b. Explaining it to the person

Many lf-godot-gd-utils users are not programmers. When you use a library class for them:

- Say in plain words what it does and which class it is, and link its module page
  (`<library>/src/<group>/lf_<name>/README.md`); its *Step by step* section is written for them.
- If they must do something in the Godot editor (add a node, attach a script, set an
  Inspector value, press F6), give numbered steps with the editor's real names, and say
  what they should see when it works.
- Explain any jargon you can't avoid (signal, `await`, delta, ms vs seconds) in a few
  words, as the module pages do.

## 2. Nothing fits: decide where the new code lives

Ask: *would a different game need this unchanged?*

- **No** (it knows this game's rules, data or scenes): write it in the game.
- **Yes** (generic: no game classes, no game constants): add it to lf-godot-gd-utils (step 3), then
  use it from the game. If lf-godot-gd-utils is a copy you update from upstream (a release zip or the
  Asset Library) rather than a repository you maintain, edits inside it would be lost on
  the next update: keep the generic code in the project's own utilities folder instead,
  and consider contributing it to LF.

When in doubt, write it in the game first and promote it once a second use appears.

## 3. Adding or changing something in lf-godot-gd-utils

1. Follow the library's conventions (`LF_INDEX.md` → Conventions):
   - Files and folders are `lf_snake_case`, classes `LFPascalCase`.
   - Tabs, no trailing semicolons, `and`/`or` instead of `&&`/`||`.
   - Typed signatures, a `##` doc comment on every public member, and no GDScript
     warnings.
   - No magic values: every meaningful number or string is a named constant
     (`DEFAULT_<NAME>` for public defaults). No game concepts in code, doc comments or
     tests; READMEs may use game examples to teach.
   - One folder per module: `src/<group>/lf_<name>/` with the source, a `README.md` in its
     siblings' template (tagline, info table, When to use it, Step by step for a
     non-programmer, API, Usage, Notes), and `tests/test_lf_<name>.gd` (GUT).
2. Keep it generic and self-contained: it depends only on Godot and other library classes,
   never on the project's classes, constants, folders, autoloads or input actions, and
   never on where lf-godot-gd-utils is installed (resolve paths from a script's `resource_path`).
3. Write the tests first, and check that a fix's test fails without the fix.
4. Register the `class_name`: run `godot --headless --import` once from the project root.
5. Update the index:
   - Add a row to the group table in `LF_INDEX.md` for every class, with the class name
     (or `Outer.Inner` for a public inner class) in the row's first cell, and a "Find it
     by task" line if it answers a new need. Changing an API means updating its row's
     key members. Keep every row at its table header's cell count (no `|` in cells).
   - Run `<library>/tests/test_lf_index.gd`. It fails on a class missing from a row's first
     cell, a misaligned table, or a module without a README or tests.

## 4. Before finishing

- If any code was written that looks reusable, run through step 2 once more.
- If lf-godot-gd-utils changed, run its tests: `test_lf_index.gd` and the module's own tests must pass.
  In the library's own repository, also run `ci/check_install.sh` (it fails on any GDScript
  warning). Never relax a check to get it green; fix the module instead.

Run one test file with GUT from the project root, selecting it by name (the project's
`.gutconfig.json` must list `<library>` in `dirs`, with subdirectories):

```
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gselect=test_lf_<name>.gd -gexit
```
