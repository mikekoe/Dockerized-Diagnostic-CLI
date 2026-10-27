#!/usr/bin/env bash
# test.sh - Tests for the diagnostic tool and its Docker image.
#
# Usage: ./test.sh [--no-docker]
#   Builds the image (diagnostic-tool) and tests it: help, system, disk,
#   network and invalid-command handling, plus container properties and
#   Docker Compose. The same CLI tests are also run against app/diagnostic.sh.
#   --no-docker  run only the script-level tests (no image build).
#
# Exit code: 0 if no test failed, 1 otherwise.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

IMAGE="diagnostic-tool"
PASS=0; FAIL=0; SKIP=0
RUN_DOCKER=1
[ "${1:-}" = "--no-docker" ] && RUN_DOCKER=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }

# check "description" expected_exit "regex or empty" command...
check() {
    local desc="$1" want_rc="$2" pattern="$3"; shift 3
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want_rc" ]; then
        fail "$desc (expected exit $want_rc, got $rc)"
    elif [ -n "$pattern" ] && ! grep -qiE "$pattern" <<< "$out"; then
        fail "$desc (output did not match '$pattern')"
    else
        pass "$desc"
    fi
}

# run_cli_tests <label> <command prefix...>
run_cli_tests() {
    local label="$1"; shift
    local D=("$@")
    echo
    echo "== CLI tests: $label =="

    check "help shows usage"                    0 "usage"            "${D[@]}" help
    check "--help shows usage"                  0 "usage"            "${D[@]}" --help
    # In the image, "no command" runs the default CMD (help); that is tested separately.
    if [ "${D[0]}" != "docker" ]; then
        check "no command -> exit 2"            2 "missing command"  "${D[@]}"
    fi
    check "invalid command -> exit 2"           2 "unknown command"  "${D[@]}" bogus
    check "system prints system info"           0 "hostname"         "${D[@]}" system
    check "system shows kernel"                 0 "kernel"           "${D[@]}" system
    check "system rejects extra argument"       2 "no arguments"     "${D[@]}" system extra
    check "disk prints filesystem usage"        0 "filesystem"       "${D[@]}" disk
    check "disk rejects extra argument"         2 "no arguments"     "${D[@]}" disk extra
    check "network without host -> exit 2"      2 "requires a <host>" "${D[@]}" network
    check "network with 2 args -> exit 2"       2 "exactly one"      "${D[@]}" network a b
    check "network rejects invalid host"        2 "not a valid"      "${D[@]}" network "bad host!"
    check "network rejects leading dash"        2 "not a valid"      "${D[@]}" network -bad
    check "network unresolvable host -> exit 1" 1 "unresolved"       "${D[@]}" network nosuchhost.invalid
    if [ "${D[0]}" = "docker" ] || command -v ping >/dev/null 2>&1; then
        check "network localhost is reachable"  0 "reachable"        "${D[@]}" network localhost
    else
        skip "network localhost (ping is not installed on this machine)"
    fi
}

echo "Diagnostic tool tests"
echo "====================="

# ---------- Syntax ----------
echo
echo "== Syntax =="
for f in app/diagnostic.sh app/health-check.sh test.sh grade.sh; do
    if [ -f "$f" ]; then
        bash -n "$f" 2>/dev/null && pass "bash -n $f" || fail "bash -n $f"
    else
        fail "missing file: $f"
    fi
done

# ---------- Docker image tests ----------
if [ "$RUN_DOCKER" -eq 0 ]; then
    echo
    echo "== Docker image tests =="; skip "disabled with --no-docker"
elif ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo
    echo "== Docker image tests =="
    skip "Docker is not installed or the daemon is not running (start Docker to test the image)"
else
    echo
    echo "== Docker build =="
    if docker build -q -t "$IMAGE" . >/dev/null 2>&1; then
        pass "docker build -t $IMAGE ."

        run_cli_tests "container (docker run --rm $IMAGE)" docker run --rm "$IMAGE"

        echo
        echo "== Container properties =="
        check "default command shows help"       0 "usage"   docker run --rm "$IMAGE"
        check "system reports running in Docker" 0 "running in docker +: yes" docker run --rm "$IMAGE" system
        check "app is executable in the image"   0 ""        docker run --rm --entrypoint test "$IMAGE" -x /usr/local/bin/diagnostic
        check "runs as non-root user"            0 "^diag$"  docker run --rm --entrypoint id "$IMAGE" -un
        check "health check reports healthy"     0 "healthy" docker run --rm --entrypoint /app/health-check.sh "$IMAGE"
        check "works with read-only filesystem"  0 "usage"   docker run --rm --read-only "$IMAGE" help

        echo
        echo "== Docker Compose =="
        if docker compose version >/dev/null 2>&1; then
            check "compose.yaml is valid"        0 ""        docker compose config -q
            check "compose run: system"          0 "hostname" docker compose run --rm diagnostic system
            check "compose run: disk"            0 "filesystem" docker compose run --rm diagnostic disk
            check "compose run: help"            0 "usage"   docker compose run --rm diagnostic help
            check "compose run: invalid command" 2 "unknown command" docker compose run --rm diagnostic bogus
        else
            skip "docker compose is not available"
        fi
    else
        fail "docker build -t $IMAGE ."
    fi
fi

# ---------- Script-level tests (no Docker) ----------
run_cli_tests "script (app/diagnostic.sh)" bash app/diagnostic.sh

if [ -r /proc/meminfo ]; then
    echo
    echo "== Health check (script) =="
    check "health-check reports healthy" 0 "healthy" bash app/health-check.sh
fi

# ---------- Summary ----------
echo
echo "====================="
echo "Passed: $PASS   Failed: $FAIL   Skipped: $SKIP"
if [ "$SKIP" -gt 0 ]; then
    echo "Note: skipped tests did not run; start Docker for the full suite."
fi
[ "$FAIL" -eq 0 ]
