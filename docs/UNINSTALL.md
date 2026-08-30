# Uninstalling

`./uninstall.sh` (from the install directory; needs `.env`) stops and deletes every container, removes the cron lines and `active/`, deletes `tailscale.env`, the override, the Controllarr clone, `warden.env`, `INSTALL-SUMMARY.txt` and **all of `CONFIG_DIR`**. Media is kept unless you say otherwise. Everything is logged to `uninstall-<timestamp>.log`.

**Before you start:** copy `CONFIG_DIR/.backup-passphrase` somewhere safe if you use backups (the archives in `BACKUP_DIR` survive, the key does not — [BACKUP-RESTORE.md](BACKUP-RESTORE.md)); note that `warden.env` and the summary go while `secrets.env` stays. Remove the machine in Tailscale's admin console if it was on.

**It asks:** type `yes`; *Also remove the downloaded Docker images?* (default no); *Also PURGE the media library?* (default no).

**How:** `docker compose --env-file .env --profile '*' down --remove-orphans --volumes`, then every crontab line containing `<repo>/active` and their `/tmp/mediastack-*.lock` files. Root-owned files are removed through a throwaway `alpine` container, so no `sudo` is needed; if even that fails you get a `[!]` with the path.

**Kept:** the repo, `.env`, `secrets.env`, the logs, `BACKUP_DIR`, `DATA_DIR` (unless purged), images (unless removed), host packages. A later `./install.sh` is therefore a clean reinstall with the same answers and passwords; anything that lived only in `CONFIG_DIR` (watch history, users, requests) is gone unless you restore a backup.

Finish by hand if you want: `rm -rf media-stack`, `rm -rf /srv/media/backups`, `rm -rf /srv/media/data`, `docker image prune -a`. Verify: `docker ps -a`, `docker volume ls`, `docker network ls | grep mediastack`, `crontab -l | grep media-stack/active`, `ls /srv/media/config` — all empty.

## Partial teardown

Re-run `./install.sh` and answer no to the part: Tailscale, ntfy (its container is retired, `CONFIG_DIR/ntfy` stays), the automation or backups (the crontab is rewritten). To stop everything but keep it installed: `docker compose --env-file .env down` / `up -d`.
