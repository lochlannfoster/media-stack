#!/usr/bin/env python3
"""Deterministic checks on docker-compose.yml beyond `docker compose config` (docs/DEVELOPMENT.md):
  - every service's container_name equals its service key (the installer and the panel look up by name)
  - a healthcheck and `labels: [autoheal=true]` come as a pair (autoheal only restarts labelled containers)
  - every ${VAR} the file interpolates without a default is declared in .env.example
  - the control panel keeps its read-only Docker socket, its /health healthcheck and port 3002
Exit 0 when clean; the findings are the output. Uses PyYAML with the base loader.
"""
import os, re, sys
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPOSE = os.path.join(ROOT, "docker-compose.yml"); ENV = os.path.join(ROOT, ".env.example")
VAR = re.compile(r"\$\{([A-Z0-9_]+)(:?[-?][^}]*)?\}")
# other people's images with no cheap HTTP probe, or deliberately unlabelled
NO_HEALTHCHECK_OK = {"autoheal", "ntfy"}


def main():
    problems = []
    raw = open(COMPOSE, encoding="utf-8").read()
    doc = yaml.load(raw, Loader=yaml.BaseLoader)
    services = doc.get("services") or {}
    env_keys = {ln.split("=", 1)[0].strip() for ln in open(ENV, encoding="utf-8") if "=" in ln and not ln.lstrip().startswith("#")}
    for name, svc in services.items():
        svc = svc or {}
        if svc.get("container_name") != name:
            problems.append(f"{name}: container_name is {svc.get('container_name')!r}, must equal the service key")
        labels = svc.get("labels") or []
        labels = labels if isinstance(labels, list) else [f"{k}={v}" for k, v in labels.items()]
        has_hc, has_ah = "healthcheck" in svc, any(str(l).replace(" ", "") == "autoheal=true" for l in labels)
        if has_hc != has_ah and name not in NO_HEALTHCHECK_OK:
            problems.append(f"{name}: healthcheck={'yes' if has_hc else 'no'} but autoheal label={'yes' if has_ah else 'no'} — they come as a pair")
        if not has_hc and name not in NO_HEALTHCHECK_OK:
            problems.append(f"{name}: no healthcheck (add one + the autoheal label, or list it in NO_HEALTHCHECK_OK here)")
    for m in VAR.finditer(raw):
        var, default = m.group(1), m.group(2)
        if var not in env_keys and not default:
            problems.append(f"${{{var}}} is interpolated with no default and is not in .env.example")
    cp = services.get("controllarr") or {}
    vols = [str(v) for v in (cp.get("volumes") or [])]
    if not any(v.startswith("/var/run/docker.sock:") and v.endswith(":ro") for v in vols):
        problems.append("controllarr: the Docker socket must be mounted read-only (/var/run/docker.sock:…:ro)")
    if not any(v.startswith("./controllarr/app:") and v.endswith(":ro") for v in vols):
        problems.append("controllarr: its code comes from the cloned repository, mounted read-only (./controllarr/app:/app:ro)")
    hc = " ".join(str(x) for x in ((cp.get("healthcheck") or {}).get("test") or []))
    if "3002/health" not in hc: problems.append("controllarr: healthcheck must probe http://127.0.0.1:3002/health")
    if not any(str(p).endswith(":3002") for p in (cp.get("ports") or [])): problems.append("controllarr: the container port must stay 3002")
    for p in problems: print("compose:", p)
    print(f"compose: {len(services)} services checked, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
