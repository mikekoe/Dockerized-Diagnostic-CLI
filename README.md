# Diagnostic Tool (Dockerized)

A Bash command-line diagnostic tool packaged as a Docker image. It reports
system information, checks network reachability of a host, and shows disk
usage. It can be built and run locally with Docker or Docker Compose.

## Project structure

```
assignment-2/
├── README.md
├── app/
│   ├── diagnostic.sh      # the CLI tool
│   └── health-check.sh    # container health check
├── Dockerfile
├── compose.yaml
├── .dockerignore
├── test.sh                # tests (local and Docker)
└── grade.sh               # structure and requirements checker
```

## Commands

```
diagnostic system
diagnostic network <host>
diagnostic disk
diagnostic help
```

| Command | What it does |
|---------|--------------|
| `diagnostic system` | Hostname, user, date/time, OS, kernel, architecture, uptime, load average, CPU, memory, and whether it is running in Docker |
| `diagnostic network <host>` | Validates the host, resolves it (DNS), pings it, and tests TCP ports 80 and 443. Reports `REACHABLE` if ping or any port succeeds |
| `diagnostic disk` | Filesystem usage (`df -h`), inode usage and a summary of the root filesystem |
| `diagnostic help` | Shows the commands and usage |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | A check failed (host did not resolve, host unreachable, `df` failed) |
| `2` | Invalid usage: unknown command, no command, missing argument, extra arguments or an invalid host |

### Error handling

```
$ diagnostic bogus
Error: unknown command 'bogus'.
Usage: diagnostic <command> [arguments]
...                                          (exit code 2)

$ diagnostic network
Error: 'network' requires a <host> argument.
Run 'diagnostic help' for usage.             (exit code 2)

$ diagnostic network "bad host!"
Error: 'bad host!' is not a valid hostname or IP address.
Run 'diagnostic help' for usage.             (exit code 2)
```

Errors go to stderr, so normal output stays clean for scripts and pipelines.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (Docker Desktop on macOS or Windows, Docker Engine on Linux)
- Docker Compose v2 (`docker compose`), included with Docker Desktop

Check with:

```bash
docker --version
docker compose version
```

## Build

```bash
docker build -t diagnostic-tool .
```

or with Compose:

```bash
docker compose build
```

## Run

The image is named `diagnostic-tool`. Its entrypoint is `diagnostic`, so you pass only the command:

```bash
docker run --rm diagnostic-tool help
docker run --rm diagnostic-tool system
docker run --rm diagnostic-tool disk
docker run --rm diagnostic-tool network example.com
```

With no command, the container shows the help text.

### With Docker Compose

```bash
docker compose run --rm diagnostic system
docker compose run --rm diagnostic disk
docker compose run --rm diagnostic network example.com
docker compose run --rm diagnostic help
```

`docker compose up` runs the default command (`help`) and exits.

### Without Docker

The script also runs directly on Linux (and mostly on macOS, where `/proc`
values show as "Unavailable"):

```bash
bash app/diagnostic.sh system
bash app/diagnostic.sh network localhost
```

## Health check

`app/health-check.sh` verifies that `diagnostic.sh` is present and working,
that `/proc` is readable, and that the required tools (`df`, `getent`, `ping`,
`nc`) are installed. It prints `healthy` and exits 0, or prints the reason and
exits 1. The Dockerfile registers it with `HEALTHCHECK`, and Compose uses the
same check.

Run it by hand:

```bash
docker run --rm --entrypoint /app/health-check.sh diagnostic-tool
```

## Testing

Make the scripts executable first (needed once after downloading or cloning):

```bash
chmod +x grade.sh test.sh app/*
```

```bash
./test.sh                # builds the image, tests it, then tests the script
./test.sh --no-docker    # script-level tests only (no image build)
```

`test.sh` builds `diagnostic-tool` and runs the Docker image through:

- `help`, `system`, `disk` and `network`
- invalid command handling (unknown command, no command, missing or extra arguments, invalid host) and their exit codes
- container properties: default command, non-root user, executable app, health check, read-only filesystem
- Docker Compose: `compose.yaml` validity and `docker compose run --rm diagnostic system|disk|help`

The same CLI tests also run directly against `app/diagnostic.sh`. If Docker is
not running, the Docker tests are reported as `SKIP` with a warning (they did
not run). `test.sh` exits non-zero if any test fails.

## Grading

```bash
./grade.sh
```

`grade.sh` checks:

- project structure (all required files present and non-empty)
- Bash syntax and shebangs
- executable permissions (`chmod +x grade.sh test.sh app/*`)
- Dockerfile: lightweight base image, pinned tag, `COPY app/`, `chmod`, non-root `USER`, `HEALTHCHECK`, `ENTRYPOINT`/`CMD`
- `.dockerignore`: `.git`, logs and temporary/local files
- the image build (`docker build -t diagnostic-tool .`)
- container commands: `help`, `system`, `disk`, and invalid command handling (exit code 2)
- Docker Compose: `docker compose config` and `docker compose run --rm diagnostic system`
- the test suite (`test.sh`)

It exits non-zero if any check fails. If Docker is not running, the Docker
checks are skipped and a warning is printed; start Docker and re-run for a full grade.

## Design notes

- **Small image:** `debian:bookworm-slim` plus only `iputils-ping` and
  `netcat-openbsd`; the apt cache is removed in the same layer.
- **Non-root:** the container runs as the unprivileged user `diag`.
- **Least privilege (Compose):** all Linux capabilities are dropped except
  `NET_RAW` (needed for ping), and the root filesystem is read-only with a
  `tmpfs` for `/tmp`.
- **Lean build context:** `.dockerignore` keeps everything except `app/` out of
  the build.
- **Containers share the host kernel:** inside a container, `diagnostic system`
  reports the host's kernel version, and CPU, memory and uptime come from the
  host's `/proc`. The OS name and the "Running in Docker" line show the
  container's own environment.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Cannot connect to the Docker daemon` | Start Docker Desktop (or `sudo systemctl start docker` on Linux) |
| `Permission denied` running `./test.sh` | `chmod +x grade.sh test.sh app/*` |
| `network` shows `Ping: FAILED` but TCP ports are open | The host blocks ICMP. It is still reported as `REACHABLE` through the TCP check |
| `network` shows `UNREACHABLE` for a real host | The container may have no internet access or DNS. Test with `docker run --rm diagnostic-tool network localhost` |
| `network` fails to resolve names inside Docker | Check Docker's DNS settings, or try `docker run --rm --dns 8.8.8.8 diagnostic-tool network example.com` |
| `bad interpreter: ^M` | Windows line endings. Convert the scripts to LF (`dos2unix app/*.sh *.sh`) |

## Cleanup

```bash
docker compose down --remove-orphans
docker rmi diagnostic-tool
```
