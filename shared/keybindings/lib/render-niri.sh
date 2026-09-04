#!/bin/bash
#
# Renders validated keybinding JSON into a Niri KDL `binds { }` block. The final
# stage of the pipeline (see keybindings/schema.md): the input is assumed
# already validated, so this file does not re-check the schema rules.
#
# Meant to be sourced, not executed directly.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source keybindings/lib/render-niri.sh from another script; do not run it directly" >&2
  exit 1
fi

# render_niri <validated_json>
#
# Actions with [action.niri].unsupported=true contribute no bind line but do get
# a `// <id>: unsupported - <reason>` comment, grouped after the real binds, so
# the omission is not silent.
#
# Indentation inside binds { } is 4 spaces, not this repo's usual 2, matching
# upstream niri.kdl convention: for a KDL file the format's own convention wins.
render_niri() {
  local json="$1"

  # An unrecognized modifier token raises a jq-level error naming the action id
  # and the bad token, rather than passing through or being dropped silently.
  local translated
  translated=$(jq '
    def translate_mod($id):
      if . == "SUPER" then "Mod"
      elif . == "SHIFT" then "Shift"
      elif . == "ALT" then "Alt"
      elif . == "CTRL" then "Ctrl"
      else error("action \($id) has unrecognized modifier \(.) in its key notation")
      end;

    .action |= map(
      . as $a
      | ($a.key | split("+")) as $tokens
      | ($tokens[:-1] | map(translate_mod($a.id))) as $mods
      | ($tokens[-1]) as $main
      | $a * {niri: {combo: (($mods + [$main]) | join("+"))}}
    )
  ' <<<"$json" 2>&1) || { echo "render_niri: $translated" >&2; return 1; }

  printf 'binds {\n'

  jq -r '
    .action[]
    | select(.niri | has("dispatch"))
    | "    \(.niri.combo) { \(.niri.dispatch); }"
  ' <<<"$translated"

  jq -r '
    .action[]
    | select(.niri | has("unsupported"))
    | "    // \(.id): unsupported - \(.niri.reason)"
  ' <<<"$translated"

  printf '}\n'
}
