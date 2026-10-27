#!/usr/bin/env bash
# grade.sh - Checks the assignment-2 structure and requirements.
#
# Checks: project structure, Bash syntax, executable permissions, Dockerfile,
# .dockerignore, image build, basic container commands, invalid command
# handling, Docker Compose configuration and the test suite (test.sh).
#
# Usage: chmod +x grade.sh test.sh app/*   (once)
#        ./grade.sh
# Exit code: 0 if no check failed, 1 otherwise.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

IMAGE="diagnostic-tool"
PASS=0
FAIL=0
SKIP=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP+1)); }

# has "description" "regex" file
has() {
    if [ -f "$3" ] && grep -qiE "$2" "$3"; then pass "$1"; else fail "$1"; fi
}

# expect "description" expected_exit "regex or empty" command...
expect() {
    local desc="$1" want="$2" pattern="$3"; shift 3
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want" ]; then
        fail "$desc (expected exit $want, got $rc)"
    elif [ -n "$pattern" ] && ! grep -qiE "$pattern" <<< "$out"; then
        fail "$desc (output did not match '$pattern')"
    else
        pass "$desc"
    fi
}

DOCKER_OK=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then DOCKER_OK=1; fi

echo "================================="
echo "Grader - assignment-2"
echo "================================="

# ---------- Required files ----------
echo
echo "-- Project structure --"
for f in README.md app/diagnostic.sh app/health-check.sh Dockerfile compose.yaml .dockerignore test.sh grade.sh; do
    [ -f "$f" ] && pass "Required file exists: $f" || fail "Missing required file: $f"
done
for f in .dockerignore Dockerfile compose.yaml README.md; do
    [ -s "$f" ] && pass "Not empty: $f" || fail "Empty or missing: $f"
done

# ---------- Bash syntax ----------
echo
echo "-- Bash syntax --"
for f in app/diagnostic.sh app/health-check.sh test.sh grade.sh; do
    if [ -f "$f" ]; then
        head -1 "$f" | grep -q '^#!.*bash' && pass "Has bash shebang: $f" || fail "No bash shebang: $f"
        bash -n "$f" 2>/dev/null && pass "Valid syntax: $f" || fail "Syntax error: $f"
    fi
done

# ---------- Executable permissions ----------
echo
echo "-- Executable permissions (chmod +x grade.sh test.sh app/*) --"
for f in grade.sh test.sh app/diagnostic.sh app/health-check.sh; do
    [ -x "$f" ] && pass "Executable: $f" || fail "Not executable: $f"
done

# ---------- Dockerfile ----------
echo
echo "-- Dockerfile --"
has "FROM instruction"                    '^FROM '                        Dockerfile
if grep -iE '^FROM ' Dockerfile 2>/dev/null | grep -qiE 'alpine|slim|busybox|distroless|scratch'; then
    pass "Lightweight base image"
else
    fail "Lightweight base image (alpine, *-slim, busybox, distroless)"
fi
if grep -iE '^FROM ' Dockerfile 2>/dev/null | grep -qiE ':latest|^FROM [^: ]+( |$)'; then
    fail "Base image is pinned to a tag (not latest/untagged)"
else
    pass "Base image is pinned to a tag (not latest/untagged)"
fi
has "Installs packages with --no-install-recommends / --no-cache" 'no-install-recommends|--no-cache' Dockerfile
has "apt cache cleaned (or apk --no-cache)"  'rm -rf /var/lib/apt/lists|apk add --no-cache' Dockerfile
has "Copies app/ into the image"          '^COPY +app/?'                  Dockerfile
has "Sets executable permissions (chmod)" 'chmod'                         Dockerfile
has "Runs as a non-root user (USER)"      '^USER +[^ ]+'                  Dockerfile
if grep -qiE '^USER +(root|0)( |$)' Dockerfile 2>/dev/null; then fail "USER is not root"; else pass "USER is not root"; fi
has "HEALTHCHECK instruction"             '^HEALTHCHECK '                 Dockerfile
has "ENTRYPOINT and/or CMD"               '^(ENTRYPOINT|CMD) '            Dockerfile
has "'diagnostic' command installed"      'diagnostic'                    Dockerfile

# ---------- .dockerignore ----------
echo
echo "-- .dockerignore --"
has "Ignores .git"                        '^\.git$'                       .dockerignore
has "Ignores logs"                        '^(\*\.log|logs/?)$'            .dockerignore
has "Ignores temporary/local files"       'tmp|\.swp|\.DS_Store|\.env'    .dockerignore

# ---------- compose.yaml (static) ----------
echo
echo "-- compose.yaml --"
has "Defines services"                    '^services:'                    compose.yaml
has "Service named 'diagnostic'"          '^  diagnostic:'                compose.yaml
has "Builds from the Dockerfile"          '^ +build:'                     compose.yaml
has "Sets a default command"              '^ +command:'                   compose.yaml
has "Image named $IMAGE"                  "image: +$IMAGE"                compose.yaml

# ---------- README ----------
echo
echo "-- README.md --"
has "Documents docker build"              'docker build -t diagnostic-tool'  README.md
has "Documents docker run"                'docker run --rm diagnostic-tool'  README.md
has "Documents docker compose run"        'docker compose run --rm diagnostic' README.md
for c in system network disk help; do
    has "Documents command: $c"           "diagnostic $c"                 README.md
done
has "Documents test.sh"                   'test\.sh'                      README.md
has "Documents grade.sh"                  'grade\.sh'                     README.md

# ---------- Docker: build, containers, compose ----------
echo
echo "-- Docker image and containers --"
if [ "$DOCKER_OK" -eq 1 ]; then
    if docker build -q -t "$IMAGE" . >/dev/null 2>&1; then
        pass "docker build -t $IMAGE ."
        expect "docker run --rm $IMAGE help"            0 "usage"           docker run --rm "$IMAGE" help
        expect "docker run --rm $IMAGE system"          0 "hostname"        docker run --rm "$IMAGE" system
        expect "docker run --rm $IMAGE disk"            0 "filesystem"      docker run --rm "$IMAGE" disk
        expect "docker run --rm $IMAGE <invalid>"       2 "unknown command" docker run --rm "$IMAGE" notacommand
        expect "docker run --rm $IMAGE network (no host)" 2 "requires a <host>" docker run --rm "$IMAGE" network
        expect "Container runs as non-root"             0 "^diag$"          docker run --rm --entrypoint id "$IMAGE" -un
    else
        fail "docker build -t $IMAGE ."
    fi

    echo
    echo "-- Docker Compose --"
    if docker compose version >/dev/null 2>&1; then
        expect "docker compose config"                  0 ""                docker compose config -q
        expect "docker compose run --rm diagnostic system" 0 "hostname"     docker compose run --rm diagnostic system
        expect "docker compose run --rm diagnostic help"   0 "usage"        docker compose run --rm diagnostic help
    else
        skip "docker compose is not available"
    fi
else
    skip "Docker is not installed or not running - image build, container and Compose checks NOT run"
fi

# ---------- Student test suite ----------
echo
echo "-- Test suite (test.sh) --"
if [ -f test.sh ]; then
    if bash test.sh >/tmp/assignment2-test.log 2>&1; then
        pass "test.sh passes ($(grep -E '^Passed:' /tmp/assignment2-test.log))"
    else
        fail "test.sh reported failures:"
        grep -E 'FAIL' /tmp/assignment2-test.log | sed 's/^/    /'
    fi
else
    fail "test.sh not found"
fi

echo
echo "================================="
echo "Passed: $PASS  Failed: $FAIL  Skipped: $SKIP"
if [ "$SKIP" -gt 0 ]; then
    echo "WARNING: $SKIP check(s) were skipped. Start Docker and re-run for a full grade."
fi
echo "================================="

[ "$FAIL" -eq 0 ]
