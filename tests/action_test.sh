#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/certify.sh"

defaults() {
  INPUT_WAIT=true
  INPUT_FAIL_ON=fail
  INPUT_TIMEOUT=900
  INPUT_POLL=5
  INPUT_SUITE=channelrush-pms-core
  INPUT_CLI_VERSION=v1.2.3
  TOSPEC_PAT=test-secret
}

assert_status() {
  local expected="$1"; shift
  set +e
  ( "$@" ) >/dev/null 2>&1
  local actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    echo "expected $expected, got $actual: $*" >&2
    ( "$@" )
    exit 1
  fi
}

defaults
validate_inputs

INPUT_WAIT=truthy
assert_status 2 validate_inputs
defaults
INPUT_FAIL_ON=errors
assert_status 2 validate_inputs
defaults
INPUT_TIMEOUT=0
assert_status 2 validate_inputs
defaults
INPUT_CLI_VERSION=v1
assert_status 2 validate_inputs

defaults
INPUT_FAIL_ON=error
assert_status 0 apply_failure_policy 1 fail
assert_status 2 apply_failure_policy 127 error
INPUT_FAIL_ON=never
assert_status 0 apply_failure_policy 127 error
INPUT_FAIL_ON=fail
assert_status 1 apply_failure_policy 1 fail

run_script_with_invalid_version() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  INPUT_WAIT=true INPUT_FAIL_ON=error INPUT_TIMEOUT=5 INPUT_POLL=1 \
    INPUT_SUITE=channelrush-pms-core INPUT_CLI_VERSION=v1 TOSPEC_PAT=test-secret \
    GITHUB_OUTPUT=/dev/null GITHUB_STEP_SUMMARY=/dev/null \
    bash "$root/scripts/certify.sh"
}
assert_status 2 run_script_with_invalid_version

run_action() {
  local cli_code="$1" fail_on="$2" download_fail="${3:-0}" checksum_fail="${4:-0}" traffic="${5:-0}"
  local root temp fakebin
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  temp="$(mktemp -d)"; fakebin="$temp/bin"; mkdir -p "$fakebin"
  trap 'rm -rf "$temp"' RETURN

  printf '#!/usr/bin/env bash\n[[ "$1" == "-s" ]] && echo Linux || echo x86_64\n' > "$fakebin/uname"
  printf '#!/usr/bin/env bash\n[[ "${FAKE_DOWNLOAD_FAIL:-0}" == 1 ]] && exit 22\nout=""\nwhile [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && { out="$2"; shift 2; continue; }; shift; done\n: > "$out"\n' > "$fakebin/curl"
  printf '#!/usr/bin/env bash\n[[ "${FAKE_CHECKSUM_FAIL:-0}" == 1 ]] && exit 1 || exit 0\n' > "$fakebin/sha256sum"
  printf '#!/usr/bin/env bash\ndir=""\nwhile [[ $# -gt 0 ]]; do [[ "$1" == -C ]] && { dir="$2"; shift 2; continue; }; shift; done\nprintf %s "#!/usr/bin/env bash
echo \"cli:\$*\" >> \"\$FAKE_LOG\"
if [[ \"\$1\" == remediation ]]; then exit 0; fi
for arg in \"\$@\"; do [[ \"\$arg\" == --wait ]] && exit \"\${FAKE_CLI_CODE:-0}\"; done
exit 0
" > "$dir/tospec"\n' > "$fakebin/tar"
  chmod +x "$fakebin"/*

  local traffic_command=""
  [[ "$traffic" == 1 ]] && traffic_command='echo traffic >> "$FAKE_LOG"'
  set +e
  PATH="$fakebin:$PATH" FAKE_LOG="$temp/log" FAKE_CLI_CODE="$cli_code" FAKE_DOWNLOAD_FAIL="$download_fail" \
    FAKE_CHECKSUM_FAIL="$checksum_fail" INPUT_WAIT=true INPUT_FAIL_ON="$fail_on" \
    INPUT_TIMEOUT=5 INPUT_POLL=1 INPUT_SUITE=channelrush-pms-core INPUT_CAPS="" \
    INPUT_CLI_VERSION=v1.2.3 INPUT_TRAFFIC_COMMAND="$traffic_command" TOSPEC_PAT=test-secret \
    GITHUB_OUTPUT="$temp/output" GITHUB_STEP_SUMMARY="$temp/summary" \
    bash "$root/scripts/certify.sh"
  local result=$?
  set -e

  if [[ "$traffic" == 1 ]]; then
    local first second third
    first="$(sed -n '1p' "$temp/log")"
    second="$(sed -n '2p' "$temp/log")"
    third="$(sed -n '3p' "$temp/log")"
    [[ "$first" == cli:run* && "$first" != *--wait* ]]
    [[ "$second" == traffic ]]
    [[ "$third" == cli:run*--wait* ]]
  fi
  if [[ "$cli_code" == 1 && "$download_fail" == 0 && "$checksum_fail" == 0 ]]; then
    grep -q '^cli:remediation$' "$temp/log"
    grep -q 'ToSpec certification: fail' "$temp/summary"
  fi
  return "$result"
}

assert_status 2 run_action 0 error 1 0
assert_status 2 run_action 0 error 0 1
assert_status 2 run_action 127 error
assert_status 0 run_action 1 error
assert_status 1 run_action 1 fail
assert_status 0 run_action 0 fail 0 0 1

echo "action policy tests: ok"
