strapd_log_to_stdout() {
  [[ ${STRAPD_LOG_TO_STDOUT:-} == "1" || -z ${STRAPD_INSTALL_LOG_FILE:-} ]]
}

strapd_log_line() {
  if strapd_log_to_stdout; then
    echo "$1"
  else
    echo "$1" >>"$STRAPD_INSTALL_LOG_FILE"
  fi
}

start_install_log() {
  if ! strapd_log_to_stdout; then
    mkdir -p "$(dirname "$STRAPD_INSTALL_LOG_FILE")"
    touch "$STRAPD_INSTALL_LOG_FILE"
    chmod 666 "$STRAPD_INSTALL_LOG_FILE" 2>/dev/null || true
  fi

  export STRAPD_START_TIME="${STRAPD_START_TIME:-$(date '+%Y-%m-%d %H:%M:%S')}"
  export STRAPD_START_EPOCH="${STRAPD_START_EPOCH:-$(date +%s)}"

  strapd_log_line "=== strapd Setup Started: $STRAPD_START_TIME ==="
}

stop_install_log() {
  local end_time end_epoch duration mins secs
  end_time=$(date '+%Y-%m-%d %H:%M:%S')
  end_epoch=$(date +%s)

  strapd_log_line "=== strapd Setup Completed: $end_time ==="

  if [[ -n ${STRAPD_START_EPOCH:-} ]]; then
    duration=$((end_epoch - STRAPD_START_EPOCH))
    mins=$((duration / 60))
    secs=$((duration % 60))
    strapd_log_line "strapd setup: ${mins}m ${secs}s"
  fi
}

run_logged() {
  local script="$1"
  local exit_code errexit_was_set=0

  strapd_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $script"

  case $- in
    *e*)
      errexit_was_set=1
      set +e
      ;;
  esac

  local runner=(bash -eE)
  if [[ ${STRAPD_INSTALL_DEBUG:-} == "1" ]]; then
    runner=(bash -x -eE)
  fi

  if strapd_log_to_stdout; then
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' \
      "${runner[@]}" -c 'source "$1"' bash "$script" </dev/null 2>&1
  else
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: ' \
      "${runner[@]}" -c 'source "$1"' bash "$script" </dev/null >>"$STRAPD_INSTALL_LOG_FILE" 2>&1
  fi

  exit_code=$?
  (( errexit_was_set )) && set -e

  if (( exit_code == 0 )); then
    strapd_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $script"
  else
    strapd_log_line "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $script (exit code: $exit_code)"
  fi

  return $exit_code
}
