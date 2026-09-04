# Keybinding TOML schema

Source of truth for every bindable action, rendered per-compositor by
`bin/strapd-keybindings-generate`.

## `[[action]]` fields

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Stable, dotted, never reused for a different action once shipped. Unique across the whole file, checked **after** `repeat` expansion (see below), since a literal `id = "workspace.focus.{n}"` is a template, not a real id, until expanded. |
| `category` | yes | Groups actions for cheatsheet and menu display: `window`, `workspace`, `layout`, `session`, `media`, `apps`, `utilities`. |
| `description` | yes | Shown to users. Not a code comment. |
| `key` | yes | Canonical `MOD+MOD+KEY` notation. Translating a modifier name into a backend's own syntax, Sway's `$mod` for instance, is the renderer's job, not the schema's. |
| `repeat` | no | `{ var = "n", range = [start, end] }`. When present, `{n}` in `id`, `description`, `key`, and any `dispatch` string is expanded by simple string substitution over the inclusive range. This is the only templating the schema supports. |
| `[action.<backend>]` | yes, one per known backend | See below. |

## Per-backend tables

The known backends are `niri`, `sway` and `mango`, the three compositors v1
ships. A fourth doesn't require touching this file's validation logic. The
validator's backend list is a parameter, not a hardcoded constant, so a new
backend only has to be added to `KNOWN_BACKENDS` in
`bin/strapd-keybindings-generate` alongside its own
`keybindings/lib/render-<backend>.sh`.

Every action must declare an `[action.<backend>]` table for each of them. That
table must set **exactly one** of:

- `dispatch`, the native command string that compositor's config expects for
  this action, including any arguments it takes (`focus-workspace 3`,
  `workspace number 3`, `view,3,0`).
- `unsupported = true` plus a non-empty `reason`, documenting that this action
  has no equivalent on that compositor. Niri's scrolling-tiling model has no
  manual split-direction concept, Sway has no built-in workspace overview, and
  Mango has nine tags and no tenth.

A table that sets both, or neither, is a validation error. A table missing
entirely for a known backend is also a validation error. There is no silent
fallback.

Which backend disagrees changes per action, and that's deliberate. An action
`unsupported` on one backend is routinely a plain `dispatch` on another. In
`keybindings/actions.toml`, `layout.toggle_split` is unsupported on niri and
bound on the other two; `layout.toggle_overview` is unsupported on sway and
bound on the other two; `workspace.focus.10` is unsupported on mango and bound
on the other two. Nothing in the schema treats one compositor as the reference
the others approximate.

## Validation rules (generator must run all of these before rendering anything)

1. Every `id` is unique **after** `repeat` expansion.
2. Every action has an `[action.<backend>]` table for every backend in the generator's known-backend list.
3. Every backend table sets exactly one of `dispatch` / `unsupported`.
4. `unsupported = true` requires a non-empty `reason`.

Any violation fails the build, with a non-zero exit and a message identifying
the offending action id and rule.

## Example

```toml
[[action]]
id = "window.close"
category = "window"
description = "Close focused window"
key = "SUPER+W"

  [action.niri]
  dispatch = "close-window"

  [action.sway]
  dispatch = "kill"

  [action.mango]
  dispatch = "killclient"

[[action]]
id = "layout.toggle_split"
category = "layout"
description = "Toggle window split direction"
key = "SUPER+J"

  [action.niri]
  unsupported = true
  reason = "Scrolling-tiling model has no manual split-direction concept"

  [action.sway]
  dispatch = "layout toggle split"

  [action.mango]
  unsupported = true
  reason = "Mango switches whole named layouts, with no split direction to toggle"

[[action]]
id = "workspace.focus.{n}"
category = "workspace"
description = "Switch to workspace {n}"
key = "SUPER+{n}"
repeat = { var = "n", range = [1, 10] }

  [action.niri]
  dispatch = "focus-workspace {n}"

  [action.sway]
  dispatch = "workspace number {n}"

  [action.mango]
  dispatch = "view,{n},0"
```

## What a renderer owns

Everything mechanical and identical across every action, so it isn't duplicated
per action in the data:

- **Modifier translation.** `SUPER`/`SHIFT`/`ALT`/`CTRL` become
  `Mod`/`Shift`/`Alt`/`Ctrl` for niri and `$mod`/`Shift`/`Mod1`/`Control` for
  sway. Mango already spells them the canonical way, so its map is an identity,
  kept as a map anyway so an unrecognized token can't reach mango's parser as a
  key name. An unrecognized modifier is an error naming the action and the
  token, on every backend, not a passthrough.
- **Key-name conventions.** The sway and mango renderers lowercase a
  single-letter key, because both bind on X keysym names, where `W` is the
  shifted keysym and `SUPER+W` would silently mean Super+Shift+w.
- **The line's own shape.** Niri wraps binds in `binds { }` and writes
  `Mod+W { close-window; }`; sway writes `bindsym $mod+w kill`; mango writes
  `bind=SUPER,w,killclient`, joining modifiers with `+` and separating them from
  the key with a comma.
- **Whatever else makes the output a standalone config.** The sway renderer
  emits the `set $mod Mod4` it then binds against; the other two need nothing
  extra. Each backend's output is a complete config file its compositor will
  validate on its own, which is what
  `test/acceptance.d/keybindings-*-validate-test.sh` relies on.

## Where the rendered files land

`bin/strapd-keybindings-generate` prints one backend's config to stdout and
stops there. `bin/strapd-refresh-keybindings` is what puts them on disk. It
renders every backend the generator reports from `--list-backends` into
`~/.local/state/strapd/keybindings/` as `niri.kdl`, `sway.conf` and
`mango.conf`, each with a "do not edit" header in that file's own comment
syntax. Those are the files a compositor config includes.

Two properties matter to anything calling it:

- **Its source is the user's table if there is one.**
  `~/.config/strapd/keybindings.toml` wins over the shipped
  `keybindings/actions.toml`. An update improves the defaults for everyone who
  hasn't taken the file over, and overwrites nobody who has.
- **A table that fails validation changes nothing.** Every backend renders into
  a staging directory first and moves into place only once all of them
  succeeded. The compositor reading these files is running while the command
  runs, and niri reloads its includes on change.
