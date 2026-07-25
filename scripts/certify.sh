#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "::error::$*" >&2
  return 2
}

validate_inputs() {
  case "${INPUT_WAIT:-}" in true|false) ;; *) die "wait must be true or false"; return ;; esac
  case "${INPUT_FAIL_ON:-}" in fail|error|never) ;; *) die "fail-on must be fail, error, or never"; return ;; esac
  [[ "${INPUT_TIMEOUT:-}" =~ ^[1-9][0-9]*$ ]] || { die "timeout must be a positive integer"; return; }
  [[ "${INPUT_POLL:-}" =~ ^[1-9][0-9]*$ ]] || { die "poll-interval must be a positive integer"; return; }
  [[ -n "${INPUT_SUITE:-}" ]] || { die "suite is required"; return; }
  [[ -n "${TOSPEC_PAT:-}" ]] || { die "pat is required"; return; }
  [[ "${INPUT_CLI_VERSION:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { die "cli-version must be an immutable semantic release tag such as v1.2.3"; return; }
}

resolve_rid() {
  local os arch
  os="$(uname -s)"; arch="$(uname -m)"
  case "$os" in
    Linux) plat=linux ;;
    Darwin) plat=osx ;;
    MINGW*|MSYS*|CYGWIN*) plat=win ;;
    *) die "unsupported runner OS: $os"; return ;;
  esac
  case "$arch" in
    x86_64|amd64) cpu=x64 ;;
    arm64|aarch64) cpu=arm64 ;;
    *) die "unsupported runner arch: $arch"; return ;;
  esac
  rid="${plat}-${cpu}"
}

apply_failure_policy() {
  local code="$1" result="$2"
  case "$INPUT_FAIL_ON" in
    never) return 0 ;;
    error) [[ "$result" == error ]] && return 2 || return 0 ;;
    fail) return "$code" ;;
  esac
}

unexpected_error() {
  local ignored_code="$?"
  trap - ERR
  echo "result=error" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "exit-code=2" >> "${GITHUB_OUTPUT:-/dev/null}"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "## ToSpec certification: error" >> "$GITHUB_STEP_SUMMARY"
  fi
  if [[ "${INPUT_FAIL_ON:-fail}" == never ]]; then
    exit 0
  fi
  exit 2
}

main() {
  validate_inputs
  resolve_rid

  local base path workdir asset bin code result
  base="https://github.com/ToSpec-Dev/cli/releases"
  path="$base/download/$INPUT_CLI_VERSION"
  workdir="$(mktemp -d)"
  trap "rm -rf -- '$workdir'" EXIT

  if [[ "$plat" == win ]]; then
    asset="tospec-${rid}.zip"
    bin="$workdir/tospec.exe"
  else
    asset="tospec-${rid}.tar.gz"
    bin="$workdir/tospec"
  fi

  curl --retry 3 --retry-all-errors -sSLf "$path/$asset" -o "$workdir/$asset"
  curl --retry 3 --retry-all-errors -sSLf "$path/$asset.sha256" -o "$workdir/$asset.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$workdir" && sha256sum -c "$asset.sha256")
  else
    local expected actual
    expected="$(awk '{print $1}' "$workdir/$asset.sha256")"
    actual="$(shasum -a 256 "$workdir/$asset" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || { die "CLI checksum mismatch"; return; }
  fi

  if [[ "$plat" == win ]]; then
    unzip -q "$workdir/$asset" -d "$workdir"
  else
    tar -xzf "$workdir/$asset" -C "$workdir"
    chmod +x "$bin"
  fi

  export TOSPEC_STATE_FILE="$workdir/session"
  local -a args=(run --suite "$INPUT_SUITE" --timeout "$INPUT_TIMEOUT" --poll-interval "$INPUT_POLL")
  while IFS= read -r cap; do
    [[ -n "$cap" ]] && args+=(--capability "$cap")
  done <<< "${INPUT_CAPS:-}"

  trap - ERR
  set +e
  if [[ -n "${INPUT_TRAFFIC_COMMAND:-}" ]]; then
    "$bin" "${args[@]}"
    code=$?
    if [[ "$code" -eq 0 ]]; then
      bash -euo pipefail -c "$INPUT_TRAFFIC_COMMAND"
      code=$?
    fi
    if [[ "$code" -eq 0 && "$INPUT_WAIT" == true ]]; then
      "$bin" "${args[@]}" --wait
      code=$?
    fi
  elif [[ "$INPUT_WAIT" == true ]]; then
    "$bin" "${args[@]}" --wait
    code=$?
  else
    "$bin" "${args[@]}"
    code=$?
  fi
  set -e
  trap unexpected_error ERR

  case "$code" in 0) result=pass ;; 1) result=fail ;; *) result=error ;; esac
  echo "result=$result" >> "$GITHUB_OUTPUT"
  echo "exit-code=$code" >> "$GITHUB_OUTPUT"

  if [[ "$code" -ne 0 ]]; then
    {
      echo "## ToSpec certification: $result"
      echo
      echo '```markdown'
      "$bin" remediation || echo "(remediation report unavailable)"
      echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
  else
    echo "## ToSpec certification: passed ✅" >> "$GITHUB_STEP_SUMMARY"
  fi

  trap - ERR
  apply_failure_policy "$code" "$result"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -E
  trap unexpected_error ERR
  main "$@"
fi
