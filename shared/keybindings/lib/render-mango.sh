#!/bin/bash
#
# Renders validated keybinding JSON into MangoWC `bind=` lines. The final stage
# of the pipeline (see keybindings/schema.md): the input is assumed already
# validated, so this file does not re-check the schema rules.
#
# Meant to be sourced, not executed directly.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source keybindings/lib/render-mango.sh from another script; do not run it directly" >&2
  exit 1
fi

# render_mango <validated_json>
#
# Mango's bind line is `bind=<MODS>,<KEY>,<dispatcher>[,<args>]`. The `dispatch`
# field in the TOML is everything from the dispatcher on, commas included (e.g.
# `view,3`), because that is one unit as far as mango's parser is concerned.
#
# Actions with [action.mango].unsupported=true contribute no bind line but do
# get a `# <id>: unsupported - <reason>` comment, grouped after the real binds,
# so the omission is not silent. Same shape as render_niri and render_sway.
render_mango() {
  local json="$1"

  # Mango's modifier spelling is already canonical, so this translation is an
  # identity map that exists to reject an unrecognized token: passing the key
  # field through untouched would let a typo'd modifier reach mango's parser as
  # a key name.
  #
  # The main key is lowercased when it is a single letter: mango takes key names
  # from xev/wev, where `W` is a different keysym from `w`.
  local translated
  translated=$(jq '
    def translate_mod($id):
      if . == "SUPER" then "SUPER"
      elif . == "SHIFT" then "SHIFT"
      elif . == "ALT" then "ALT"
      elif . == "CTRL" then "CTRL"
      else error("action \($id) has unrecognized modifier \(.) in its key notation")
      end;

    def translate_key:
      if test("^[A-Za-z]$") then ascii_downcase else . end;

    .action |= map(
      . as $a
      | ($a.key | split("+")) as $tokens
      | ($tokens[:-1] | map(translate_mod($a.id))) as $mods
      | ($tokens[-1] | translate_key) as $main
      | $a * {mango: {combo: "\($mods | join("+")),\($main)"}}
    )
  ' <<<"$json" 2>&1) || { echo "render_mango: $translated" >&2; return 1; }

  jq -r '
    .action[]
    | select(.mango | has("dispatch"))
    | "bind=\(.mango.combo),\(.mango.dispatch)"
  ' <<<"$translated"

  jq -r '
    .action[]
    | select(.mango | has("unsupported"))
    | "# \(.id): unsupported - \(.mango.reason)"
  ' <<<"$translated"
}
