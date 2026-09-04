#!/bin/bash
#
# Renders validated keybinding JSON into Sway `bindsym` lines. The final stage
# of the pipeline (see keybindings/schema.md): the input is assumed already
# validated, so this file does not re-check the schema rules.
#
# Meant to be sourced, not executed directly.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source keybindings/lib/render-sway.sh from another script; do not run it directly" >&2
  exit 1
fi

# render_sway <validated_json>
#
# Actions with [action.sway].unsupported=true contribute no bindsym line but do
# get a `# <id>: unsupported - <reason>` comment, grouped after the real binds,
# so the omission is not silent.
#
# The output opens with `set $mod Mod4` rather than assuming an enclosing config
# already made it, which is what keeps it a standalone file: `sway -C -c
# <output>` validates it on its own and there is no include-ordering rule for a
# caller to get wrong.
render_sway() {
  local json="$1"

  # An unrecognized modifier token raises a jq-level error naming the action id
  # and the bad token, rather than passing through or being dropped silently.
  #
  # The main key is lowercased when it is a single letter: sway binds on X
  # keysym names, where `W` is the shifted `w`, so a literal `SUPER+W` would
  # bind Super+Shift+w.
  local translated
  translated=$(jq '
    def translate_mod($id):
      if . == "SUPER" then "$mod"
      elif . == "SHIFT" then "Shift"
      elif . == "ALT" then "Mod1"
      elif . == "CTRL" then "Control"
      else error("action \($id) has unrecognized modifier \(.) in its key notation")
      end;

    def translate_key:
      if test("^[A-Za-z]$") then ascii_downcase else . end;

    .action |= map(
      . as $a
      | ($a.key | split("+")) as $tokens
      | ($tokens[:-1] | map(translate_mod($a.id))) as $mods
      | ($tokens[-1] | translate_key) as $main
      | $a * {sway: {combo: (($mods + [$main]) | join("+"))}}
    )
  ' <<<"$json" 2>&1) || { echo "render_sway: $translated" >&2; return 1; }

  # $mod is sway's variable syntax, not a shell expansion.
  # shellcheck disable=SC2016
  printf 'set $mod Mod4\n\n'

  jq -r '
    .action[]
    | select(.sway | has("dispatch"))
    | "bindsym \(.sway.combo) \(.sway.dispatch)"
  ' <<<"$translated"

  jq -r '
    .action[]
    | select(.sway | has("unsupported"))
    | "# \(.id): unsupported - \(.sway.reason)"
  ' <<<"$translated"
}
