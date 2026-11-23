# Deployment

## Initial Ubuntu install

From a checkout of this repository on the VPS, run:

```bash
sudo bash scripts/install_ubuntu.sh
```

The installer creates a dedicated service account, SQLite data directory,
systemd service, and Nginx site for `wifi.prottushjd.tech`. It creates
`/opt/wifi-fleet-monitor/.env` with a generated `INGEST_TOKEN` if one does not
already exist. Keep that token private.

Point the DNS A record for `wifi.prottushjd.tech` at `187.52.118.25`, allow TCP
ports 80 and 443 in the VPS firewall, then issue the TLS certificate:

```bash
sudo certbot --nginx -d wifi.prottushjd.tech
```

Verify the service and local socket:

```bash
sudo systemctl status wifi-fleet-monitor
sudo stat /run/wifi-fleet-monitor/uvicorn.sock
curl --unix-socket /run/wifi-fleet-monitor/uvicorn.sock http://localhost/health
```

## Optional GitHub Actions deployment

The workflow `.github/workflows/deploy.yml` is manual only. It uploads the
checked-out source to `/tmp/wifi-fleet-monitor-deploy` on the VPS and runs the
installer. Configure these repository Actions secrets before dispatching it:

- `VPS_SSH_PRIVATE_KEY`: contents of a dedicated private SSH key authorized for
  root on the VPS. Never commit or paste this private key into the repository.
- `VPS_KNOWN_HOSTS`: a verified `known_hosts` line for `187.52.118.25`. Obtain
  the host key fingerprint through the VPS console or a trusted channel, then
  verify it before adding the line. Do not blindly trust `ssh-keyscan` output.

The public key corresponding to the private key must be in
`/root/.ssh/authorized_keys` on the VPS. The workflow does not run on pushes;
start it manually from GitHub Actions after configuring both secrets.

The installer preserves `/opt/wifi-fleet-monitor/.env` and `data/`, and backs
up existing service and Nginx configuration files before replacing them.
