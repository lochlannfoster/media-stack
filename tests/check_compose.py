#!/usr/bin/env python3
"""Deterministic checks on docker-compose.yml beyond `docker compose config` (docs/DEVELOPMENT.md):
  - every service's container_name equals its service key (the installer and the panel look up by name)
  - a healthcheck and `labels: [autoheal=true]` come as a pair (autoheal only restarts labelled containers)
  - every ${VAR} the file interpolates without a default is declared in .env.example
  - the control panel keeps its read-only Docker socket, its /health healthcheck and port 3002
  - install.sh's CONTROLLARR_REF default matches .env.example, and is a tag rather than a branch
  - the VPN routing in install.sh agrees with this file: every routable service exists, publishes the
    port gluetun would republish, and has the `dns` the override resets
Exit 0 when clean; the findings are the output. Uses PyYAML with the base loader.
"""
import os, re, sys
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPOSE = os.path.join(ROOT, "docker-compose.yml"); ENV = os.path.join(ROOT, ".env.example")
INSTALL = os.path.join(ROOT, "install.sh")
VAR = re.compile(r"\$\{([A-Z0-9_]+)(:?[-?][^}]*)?\}")
# other people's images with no cheap HTTP probe, or deliberately unlabelled
NO_HEALTHCHECK_OK = {"autoheal", "ntfy"}


def merged(svc):
    """A service's keys with YAML merge keys (`<<: *dns`) folded in. yaml.BaseLoader keeps `<<` as a
    literal key rather than merging it, so `dns` from the x-dns anchor is invisible without this."""
    out = {}
    m = svc.get("<<")
    for part in (m if isinstance(m, list) else [m] if isinstance(m, dict) else []):
        out.update(part or {})
    out.update({k: v for k, v in svc.items() if k != "<<"})
    return out


def ref_problems():
    """The panel's version is pinned in two places that must agree, and must be a tag. `main` here means
    two people installing a week apart get different panels, and a bad commit on the panel's default
    branch reaches every new install immediately."""
    out = []
    try:
        sh = open(INSTALL, encoding="utf-8").read()
        env = open(ENV, encoding="utf-8").read()
    except FileNotFoundError:
        return []
    m_sh = re.search(r'set_cfg CONTROLLARR_REF\s+"\$\(d CONTROLLARR_REF ([^)]+)\)"', sh)
    m_env = re.search(r'^CONTROLLARR_REF=(\S+)', env, re.M)
    if not m_sh or not m_env:
        return ["CONTROLLARR_REF: could not read the default from install.sh and/or .env.example"]
    sh_ref, env_ref = m_sh.group(1).strip(), m_env.group(1).strip()
    if sh_ref != env_ref:
        out.append(f"CONTROLLARR_REF: install.sh defaults to {sh_ref!r} but .env.example says {env_ref!r}")
    if sh_ref in ("main", "master", "HEAD"):
        out.append(f"CONTROLLARR_REF defaults to the branch {sh_ref!r} — pin a tag, or every install tracks the panel's tip")
    return out


def vpn_problems(services):
    """install.sh routes services through gluetun by resetting their `ports` and `dns` and republishing
    the port on gluetun. Three lists must agree or a routed service silently becomes unreachable:
    what the prompt offers, what gluetun publishes, and what the override resets."""
    out = []
    try:
        sh = open(INSTALL, encoding="utf-8").read()
    except FileNotFoundError:
        return ["install.sh is missing — the VPN routing cannot be checked"]

    m = re.search(r'VPN_ROUTABLE="([a-z ]+)\$\{OVERLAY_ROUTABLE', sh)
    offered = m.group(1).split() if m else []
    published = {svc: (var, host, cont) for svc, var, host, cont in
                 re.findall(r'_vpn_routed (\w+) && printf \'      - "\$\{([A-Z_]+):-(\d+)\}:(\d+)', sh)}
    m = re.search(r'for _s in ([a-z ]+); do', sh)
    reset = m.group(1).split() if m else []

    if not offered:
        return ["install.sh: could not find VPN_ROUTABLE — the VPN routing checks did not run"]
    if sorted(offered) != sorted(published):
        out.append(f"VPN: install.sh offers to route {offered} but gluetun publishes ports for {sorted(published)}")
    if sorted(offered) != sorted(reset):
        out.append(f"VPN: install.sh offers to route {offered} but only resets ports/dns for {reset}")

    for svc in offered:
        defn = services.get(svc)
        if defn is not None:
            defn = merged(defn)
        if defn is None:
            out.append(f"VPN: install.sh can route {svc!r}, which is not a service in docker-compose.yml")
            continue
        if "dns" not in defn:
            out.append(f"VPN: {svc} has no `dns` to reset — Docker refuses `dns` with `network_mode: service:`, "
                       f"so if one is added later without updating install.sh the routed container will not start")
        ports = [str(x) for x in (defn.get("ports") or [])]
        if not ports:
            out.append(f"VPN: {svc} publishes no port, but gluetun republishes one for it")
            continue
        var, host, cont = published.get(svc, ("", "", ""))
        if not any(f"{{{var}:-{host}}}" in pt for pt in ports):
            out.append(f"VPN: gluetun republishes {svc} as ${{{var}:-{host}}} but the service publishes {ports} — "
                       f"routing it would move the port")
    return out


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
    problems += ref_problems()
    problems += vpn_problems(services)
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
