#!/bin/bash
#
# Thin TOML -> JSON boundary layer for keybinding TOML files. Downstream code
# consumes the resulting JSON with jq and should not query TOML paths directly,
# so no field-extraction helpers belong here.
#
# Meant to be sourced, not executed directly.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source keybindings/lib/toml-read.sh from another script; do not run it directly" >&2
  exit 1
fi

# toml_to_json <file>
#
# yq silently exits 0 and prints its own --help on stdout when given a path that
# doesn't exist, misreading the missing file as a bad expression, so the
# existence check below is load-bearing rather than defensive boilerplate.
toml_to_json() {
  local file="$1"

  [[ -f $file ]] || { echo "toml_to_json: no such file: $file" >&2; return 1; }

  local json
  if ! json=$(yq -p toml -o json "$file"); then
    echo "toml_to_json: yq failed to parse $file" >&2
    return 1
  fi

  printf '%s\n' "$json"
}
