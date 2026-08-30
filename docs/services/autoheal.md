# autoheal

The restart hand. Core tier, no port, container `autoheal`.

**What it does.** Every 60 s it looks for containers labelled `autoheal=true` whose healthcheck has failed three times and restarts them. That is all.

**How to use it.** Nothing to configure. Needs attention shows *unhealthy* on a container and says autoheal will restart it; the System strip shows the container's state and last log line.

**How it fits.** Every service with a healthcheck carries the label (the pair is enforced by `tests/check_compose.py`); ntfy and autoheal itself have neither. It mounts the Docker socket **read-write** — the one container here that can start and stop others, which is why the panel's own socket is read-only.

**Common issues.**
- A container restarts every ~3 minutes → its healthcheck keeps failing for a real reason (a missing folder, a bad key); `docker logs <container>` says why, and [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) has the fixes.
- A container that shares another's network namespace loses it when that one restarts; recreate it rather than restarting it.

Related: [SERVICES.md ▸ Healthchecks and autoheal](../SERVICES.md#healthchecks-and-autoheal)
