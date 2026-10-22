# ios 5 and 6 installers can inherit mobile's bootstrap and a stale launchd socket
LAUNCHCTL_CONTEXT=direct

launchctl_cmd() {
  (
    unset LAUNCHD_SOCKET LaunchKeepContext
    case "$LAUNCHCTL_CONTEXT" in
      system) "$LAUNCHCTL" -1 "$@" ;;
      bsexec) "$LAUNCHCTL" bsexec 1 "$LAUNCHCTL" "$@" ;;
      direct) "$LAUNCHCTL" "$@" ;;
      *) return 1 ;;
    esac
  )
}

launchctl_system_context() {
  # modern launchctl names the domain explicitly; older releases expose managername
  domain="$(launchctl_cmd print system 2>/dev/null)"
  if [ $? = 0 ]; then
    case "$domain" in
      'system = {'*) launchctl_cmd list >/dev/null 2>&1; return $? ;;
    esac
  fi
  manager="$(launchctl_cmd managername 2>/dev/null)" || return 1
  [ "$manager" = System ] || return 1
  launchctl_cmd list >/dev/null 2>&1
}

select_launchctl_context() {
  for LAUNCHCTL_CONTEXT in direct system bsexec; do
    launchctl_system_context && return 0
  done
  LAUNCHCTL_CONTEXT=direct
  return 1
}

# a matching substring can be another job, and a failed list is not an empty domain
launchd_loaded() {
  jobs="$(launchctl_cmd list 2>/dev/null)" || return 2
  printf '%s\n' "$jobs" | (
    while read -r pid status job extra; do
      [ "$job" = com.shiro.shirod ] && [ -z "$extra" ] && exit 0
    done
    exit 1
  )
}

launchd_job_pid() {
  jobs="$(launchctl_cmd list 2>/dev/null)" || return 1
  printf '%s\n' "$jobs" | (
    while read -r pid status job extra; do
      if [ "$job" = com.shiro.shirod ] && [ -z "$extra" ]; then
        case "$pid" in *[!0-9]*|''|0|1) exit 1 ;; esac
        printf '%s\n' "$pid"
        exit 0
      fi
    done
    exit 1
  )
}

# ios 6 launchctl lists jobs over mach but loads and unloads them through
# /var/tmp/launchd/sock. an iphone 4s on 6.1.3 loses that file when /var/tmp is
# emptied after boot, and every load and unload fails until the next boot while
# jobs loaded at boot keep running under KeepAlive
launchd_socket_lost() {
  case "$(launchctl_cmd list com.shiro.shirod 2>&1)" in
    *'launch_msg(): Socket is not connected'*) return 0 ;;
  esac
  return 1
}

# h3lix on ios 10 accepts bootout without unloading the job, so each form is
# followed by a check of the list. callers run under set -e, hence the if
launchd_stop() {
  for step in check bootout_label bootout_plist unload remove; do
    case "$step" in
      bootout_label) launchctl_cmd bootout system/com.shiro.shirod >/dev/null 2>&1 || true ;;
      bootout_plist) launchctl_cmd bootout system "$PLIST" >/dev/null 2>&1 || true ;;
      unload) launchctl_cmd unload "$PLIST" >/dev/null 2>&1 || true ;;
      remove) launchctl_cmd remove com.shiro.shirod >/dev/null 2>&1 || true ;;
    esac
    if launchd_loaded; then state=0; else state=$?; fi
    case $state in
      1) return 0 ;;
      2) echo 'shiro: cannot verify shirod was unloaded' >&2; return 1 ;;
    esac
  done
  echo 'shiro: launchd still holds com.shiro.shirod' >&2
  return 1
}

# ios 6 launchctl refuses a plist with a one line reason, and the modern forms
# differ by release, so the reason of the last refusal is kept for the message
launchd_attempt() {
  out="$(launchctl_cmd "$@" 2>&1)" || true
  if launchd_loaded; then return 0; fi
  LAUNCHD_LAST_ERROR="$(printf '%s' "$out" | sed -n '1p')"
  return 1
}

launchd_load_and_kick() {
  launchd_attempt bootstrap system "$PLIST" || \
    launchd_attempt load -w "$PLIST" || \
    launchd_attempt load "$PLIST" || return 1
  launchctl_cmd enable system/com.shiro.shirod >/dev/null 2>&1 || true
  launchctl_cmd kickstart -k system/com.shiro.shirod >/dev/null 2>&1 || \
    launchctl_cmd start com.shiro.shirod >/dev/null 2>&1 || true
}
