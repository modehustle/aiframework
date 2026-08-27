---
name: docker-deploy
description: "Deploy a Docker stack on a Linux server securely and architecturally correctly, phase by phase, and write the STACK.md passport. Host-level actions stop and hand back to the human."
metadata:
  tier: capable
  version: 0.2.0
  source: fraim
---
# Docker Deploy Workflow for AI Agents (universal)

> A step-by-step playbook for securely and architecturally-correctly deploying **any** Docker stack on a Linux server.
> Source of rules: \"Docker Security & Deployment Blueprint\".
> Purpose: persistent context for AI development assistants (Cursor, Windsurf Cascade, etc.).
> The agent **follows the phases in order** and does not skip checklists.

## How to use this file

This file is an **engine-agnostic playbook**. The specifics of the stack being deployed (image, name, resources, volumes, ports, healthcheck, engine quirks) are supplied by the human as a **separate per-stack prompt** attached to this file. A checklist of what belongs in the per-stack prompt is in Appendix A.

> The playbook is not tied to any specific engine. Postgres/MySQL/Redis below appear only as **examples**, never as a \"default service\".

> **Two artifacts persist in the stack folder after a deploy and are how anyone re-enters it later:** `docker-compose.yml` / `.env` (*what runs*) and **`STACK.md`** — the passport (*what it is, how it is wired, how to change it safely*; Phase 10). For a one-off change weeks later, attaching `STACK.md` to the prompt is usually enough to orient the agent — and the passport instructs the agent to keep itself current, so you do not have to remember to ask.

## Standard layout (environment invariant)

- Each stack is **its own folder under `/data/apps/<project>/`** (on this server `/data` is the RAID array). Inside: `docker-compose.yml`, `.env`, `conf/`, `data/`.
- The human opens this folder in Windsurf over SSH, **so Cascade sees it as the root (`.`)**.
- Therefore **all bind paths in compose are relative** (`./data/<service>`, `./conf/...`). They automatically land under `/data/apps/<project>/` on the RAID — nothing extra to mount or relocate.
- It is **forbidden** to split config and data across different locations or to hardcode absolute paths \"somewhere else\". The data source is always `./data/...` relative to the stack root. (This eliminates the class of errors where the agent \"picks a path on its own\".)

---

## 0. Hard rules (invariants — must not be broken)

Checked ALWAYS, regardless of the task:

1. **All docker commands run via `sudo` only.** The user is not in the `docker` group (which equals root).
2. **No host passwords.** If `sudo` asks for a password, the agent stops and asks the human to type it. Do not bypass, guess, or disable `NOPASSWD`.
3. **Production containers never run on the default `bridge` network.** Only a named project network.
4. **Storage services (DBs, caches, queues — Postgres, MySQL, Redis, ClickHouse, etc.) do not publish a port to the internet.** Access is via the service's internal DNS name within the project network. If such a service must be reachable by **other machines** — only via a private network (mode C, Phase 2), never a public port.
5. **Publishing a port on `0.0.0.0`/a public IP is forbidden**, except 80/443 of the system reverse-proxy. Any other port mapping goes to **loopback (`127.0.0.1`)** or a **private interface** (VPN/private network).
6. **Processes inside the container run as non-root** (`user:` with a specific UID) wherever possible.
7. **`chown` is targeted, to the specific service UID.** Recursive `chown` on the whole stack root folder is forbidden.
8. **Every stack carries a `STACK.md` passport in its root (Phase 10).** On any task touching this stack: read it first if it exists; create it if it does not; and if the change alters anything it records (image/tag, container name, network, exposure, data layout, env, deviations) — **update it as the final step, unprompted.** A stale passport is treated as a bug, not cosmetics.

---

## 1. Pre-flight checklist (before generating any config)

```bash
# Working directory is the stack folder under /data/apps/<project>/ (opened as root in Cascade)
pwd                                  # expect /data/apps/<project>
findmnt -no SOURCE,FSTYPE,SIZE /data # confirm the intended (RAID) volume
df -h /data                          # enough space for the stack's data?

# User must NOT be in the docker group
groups | tr ' ' '\\n' | grep -x docker && echo \"WARNING: user is in the docker group\" || echo \"OK\"

# sudo requires a password (no NOPASSWD) — this is expected
sudo -n true 2>/dev/null && echo \"WARNING: passwordless sudo\" || echo \"OK: sudo is password-protected\"

# Docker and Compose v2
sudo docker version
sudo docker compose version

# Current networks (the new network name must not be taken)
sudo docker network ls
```

If the working folder is **not** under `/data/apps/`, the user is in the `docker` group, or `sudo` is passwordless — **tell the human**, do not fix it yourself.

---

## 2. Phase: service access mode (decide BEFORE generating compose)

This is the key architectural decision. For each published service, pick **exactly one** mode:

| Mode | When | `ports:` block |
|---|---|---|
| **A. Internal** (default for DBs/caches/backends) | Access needed only by other containers in the same stack | no `ports:` at all; reach by the service DNS name |
| **B. HTTP to internet** | Web UI/API exposed to the internet (e.g. n8n, dashboards) | `127.0.0.1:<port>:<port>`, then system reverse-proxy 80/443 + SSL (Phase 9) |
| **C. Non-HTTP for other machines** | DB/service reached by external servers or by you from a laptop | `<private_ip>:<port>:<port>` — ONLY a private interface (VPN/private network), NOT `0.0.0.0` |

**Mode C — details.** A public DB port on the internet is a target for scanners/brute-force/ransomware. Instead:
- **Hetzner private network** — if all participants are in the same Hetzner project.
- **VPN mesh (Tailscale/WireGuard)** — if some clients roam (a laptop from home/on the road): each device gets a stable private IP (`100.x` with Tailscale) that travels with it → no manual IP whitelist needed, access controlled by network membership.
- The port is published on the server's private IP; in `.env` this is `PRIVATE_IP=<address>`. Firewall (Phase 6) is defense-in-depth.
- Installing the VPN/private network is host-level (apt, `systemctl`, interactive auth) → **stop signal**, the human does it.

> Mode C is a controlled deviation from invariants 4/5: it is compensated by the port not being visible from the internet. State this explicitly in the per-stack prompt.

---

## 3. Phase: project network

One isolated network per independent stack. Containers of different projects do **not** share a network.

### Default: Compose creates the network (recommended)

For a self-contained stack, do **not** create the network manually. The `networks:` block in compose (Phase 4) describes an isolated network — Compose creates it on `up` and removes it on `down`.

### Variant for a shared network across stacks: external network

Needed **only** when several independent stacks must see each other (e.g. a shared reverse-proxy + apps in separate compose files):

```bash
sudo docker network create <project>-shared-network
```

And in compose the network is declared external (below), otherwise Compose creates its own `<folder>_<net>` and the manually-created one stays empty.

```yaml
networks:
  <project>-net:
    external: true
    name: <project>-shared-network
```

> ⚠️ Do not mix: either Compose manages the network or `external: true`. A manual `network create` + an internal `driver: bridge` = a dangling unused network.

---

## 4. Phase: generating `docker-compose.yml`

### Per-service checklist

- [ ] Attached to the named project network, not `bridge`.
- [ ] Access mode chosen per Phase 2 (A/B/C); `ports:` matches it.
- [ ] `user: \"<uid>:<gid>\"` (non-root), where the image allows.
- [ ] `security_opt: [no-new-privileges:true]` and `cap_drop: [ALL]`.
- [ ] Resource limits (`mem_limit`, `cpus`).
- [ ] Log rotation (`logging`).
- [ ] `restart: unless-stopped`.
- [ ] `healthcheck` on the service; for dependents — `depends_on: condition: service_healthy`.
- [ ] No `version:` field (Compose v2 ignores it).
- [ ] Secrets via `.env` (`chmod 600`), not hardcoded.
- [ ] All bind paths are **relative** (`./data/...`, `./conf/...`).

### Universal template (fill in placeholders for your stack)

```yaml
# Do NOT specify version.

networks:
  <project>-net:
    driver: bridge

services:
  <service>:
    image: <image:tag>
    container_name: <project>-<service>
    restart: unless-stopped
    user: \"<uid>:<gid>\"            # non-root. Find UID: sudo docker run --rm <image> id <user>
    networks:
      - <project>-net

    # --- PICK ONE mode from Phase 2 ---
    # A) internal: NO ports block.
    # B) HTTP to internet:
    #   ports: [\"127.0.0.1:<port>:<port>\"]
    # C) non-HTTP for other machines (private interface):
    #   ports: [\"${PRIVATE_IP}:<port>:<port>\"]   # NOT 0.0.0.0, NOT a public IP

    environment:
      - <KEY>=${<KEY>}             # secrets from .env, not hardcoded
    volumes:
      - ./data/<service>:<data path inside the image>      # relative → lands under /data/apps/<project>/
      - ./conf/<service>.conf:<config path inside the image>:ro   # if a custom config is needed
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL                        # see caveats below
    mem_limit: <Xg>
    cpus: <N>
    logging:
      driver: json-file
      options:
        max-size: \"10m\"
        max-file: \"3\"
    healthcheck:
      test: <readiness command for this image>   # examples — Appendix B
      interval: 15s
      timeout: 5s
      retries: 5

  # A dependent service reaches <service> by its DNS name within the network and waits for healthy:
  #   depends_on:
  #     <service>:
  #       condition: service_healthy
```

### Caveat on `cap_drop: [ALL]`

Ideal for standard web/app services (FastAPI/Express/Node on ports ≥1024). It will block: binding ports **<1024**, raw sockets, low-level network operations. If the container fails with permission errors — **do not remove** `cap_drop`, add back the specific capability instead:

```yaml
cap_drop: [ALL]
cap_add: [NET_BIND_SERVICE]   # example: only if a port < 1024 is truly needed
```

### Non-root for images that `chown` on startup

Many official DB images (mysql, postgres) start as root, `chown` the data, and step down to their UID via `gosu`. With `cap_drop: [ALL]` this breaks. Two clean paths:

- **Run directly as the data UID** (`user: \"<uid>:<gid>\"`) + **pre-`chown` the data dir** (Phase 5). Then the entrypoint does no chown/gosu, and `cap_drop: [ALL]` works with no `cap_add`. **Preferred.**
- Or keep the root entrypoint and add the capabilities back: `cap_add: [CHOWN, SETGID, SETUID, DAC_OVERRIDE]`.

---

## 5. Phase: volume permissions

Targeted `chown` to the specific process UID. **Never** recursive on the whole stack folder.

```bash
# 1. Find the process UID in the image (don't guess):
sudo docker run --rm <image:tag> id <user>

# 2. chown ONLY this service's data dir (path is relative to the stack root = /data/apps/<project>/):
sudo chown -R <uid>:<gid> ./data/<service>
```

> Typical UIDs (still verify live): postgres alpine = 70, postgres debian = 999, mysql/mariadb = 999, redis = 999, node images = 1000.

---

## 6. Phase: firewall (per chosen mode)

Install `ufw-docker` so Docker does not bypass UFW via iptables (needed for modes B and C):

```bash
sudo wget -O /usr/local/bin/ufw-docker \\
  https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
sudo chmod +x /usr/local/bin/ufw-docker
sudo ufw-docker install
sudo systemctl restart ufw
```

> Verify the script source. Running an external script as root is a stop signal — the human confirms.

- **Mode A:** no ports exposed → nothing to open (UFW defaults to deny incoming).
- **Mode B:** open only 80/443 for the reverse-proxy (see Phase 9). The internal port on `127.0.0.1` is unreachable from outside by design.
- **Mode C:** the port listens on a private interface. Do NOT open it to the internet. Defense-in-depth (agent outputs — human applies):
  ```bash
  sudo ufw deny <port>                                                # on the public interface
  sudo ufw route allow proto tcp from <private_subnet> to any port <port>   # e.g. 100.64.0.0/10 for Tailscale
  sudo ufw reload
  sudo ss -tlnp | grep <port>     # expect a listener ONLY on the private IP
  ```

---

## 7. Phase: launching the stack

From the stack root (`/data/apps/<project>/`, where `docker-compose.yml` lives):

```bash
sudo docker compose up -d
# Forced rebuild:
sudo docker compose up -d --build --force-recreate
```

> Before `up`, always show the human the final `docker-compose.yml` and `.env` (mask secret values) and get confirmation — especially if there is a `ports:` block (opening a port = stop signal).

---

## 8. Phase: post-deploy checks

```bash
sudo docker compose ps                  # healthy?
sudo docker compose logs -f <service>   # started without permission errors
sudo docker stats                       # resources within limits

# SECURITY CHECK: nothing extra should be exposed.
# Allowed: 127.0.0.1:*, the private IP (mode C), 80/443 reverse-proxy.
sudo docker compose ps --format '{{.Service}} -> {{.Ports}}'
sudo ss -tlnp | grep -v '127.0.0.1'
```

---

## 9. Phase: reverse-proxy (system Nginx) + SSL (certbot) — MODE B ONLY

Runs **after** the container is up and listening on `127.0.0.1:PORT` (verified in Phase 8). Goal: route a domain from the internet to the local port, terminating SSL on the system Nginx.

**Roles:** the agent generates the config and commands; the **human** applies them on the host (writing to `/etc/nginx`, issuing the certificate, `reload`) — host-level via `sudo` → stop signal.

### Step 1. Preconditions (agent, read-only)

```bash
dig +short <domain> A        # domain points to this server's IP
nginx -v
certbot --version
sudo ufw status | grep -E '80|443'
```

Opening the ports (the human does it):

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### Step 2. Agent generates the HTTP config (port 80)

Save into the project repo, **not** directly to `/etc/nginx`: `./deploy/nginx/<domain>.conf`

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name <domain>;

    client_max_body_size 25m;   # tune to the app

    location / {
        proxy_pass http://127.0.0.1:<port>;   # container port from compose
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket (if the app needs it)
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection \"upgrade\";

        proxy_read_timeout 60s;
    }
}
```

### Step 3. Human applies the config

```bash
sudo cp ./deploy/nginx/<domain>.conf /etc/nginx/sites-available/<domain>.conf
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
sudo nginx -t                 # syntax (read-only)
sudo systemctl reload nginx
```

### Step 4. SSL certificate (Let's Encrypt)

`--nginx` will add the 443 block and the 80→443 redirect itself. The human runs:

```bash
sudo certbot --nginx -d <domain>     # multiple: -d <domain> -d www.<domain>
```

Certbot interactively asks for an email and ToS consent — that is human input, the agent does not do it.

> Full control over the config: `sudo certbot certonly --nginx -d <domain>` issues only the certificate; the 443 block is written manually with paths `/etc/letsencrypt/live/<domain>/{fullchain,privkey}.pem`.

### Step 5. Verification and auto-renewal

```bash
curl -I http://<domain>      # expect 301 → https
curl -I https://<domain>     # expect the app's response
systemctl status certbot.timer
sudo certbot renew --dry-run # dry run, changes nothing
```

---

## 10. Phase: project passport (`STACK.md`) — required final artifact

The deploy is not \"done\" until the stack has a `STACK.md` in its root. This is the **re-entry document**: the single file a human or an agent reads weeks later to understand what this stack is, how it is wired, and how to change it safely — instead of reverse-engineering `docker-compose.yml` and `.env` from scratch every time.

**Why it belongs to deploy, not to bootstrap.** Every box gets a passport, including a pure off-the-shelf service (n8n, Redis) that contains none of your own code. For such a service the passport *is* the whole re-entry story. A project that also contains your own source code gets an additional, richer foundation from the separate bootstrap workflow — but that is about the *code*; `STACK.md` here is only about the *box* (image, network, exposure, data). The two are complementary layers, never duplicates.

### Self-maintenance (this is the part that solves \"I'll forget to update it\")

`STACK.md` opens with a standing directive to any agent that reads it (template in Appendix C). The rule: **whoever changes the stack updates the passport in the same task, unprompted.** Currency does not depend on the human remembering. Two independent triggers enforce it, so one forgotten attachment never silently rots the passport:

- The **passport itself** carries the directive. Since `STACK.md` is the natural file you attach to a one-off change prompt to give the agent context, the update rule rides along with the context you were attaching anyway.
- This **workflow** carries invariant 0.8. Whenever the workflow is attached for a deploy or change, the same rule applies.

> Strongest option (zero attachment): register the rule once as a persistent Windsurf workspace/global rule — \"in any `/data/apps/*` stack, treat `STACK.md` as authoritative and update it on any change\". Then the discipline loads every session no matter what you attach or forget to attach.

### Generating it

Fill the Appendix C template from the facts established during this deploy: access mode, images/tags (pinned), network, what is exposed and where, data dirs, any deviations from this workflow, and the originating per-stack prompt. Keep it to roughly half a page — a fixed-schema fact sheet, not a wiki. Show it to the human together with the rest of the deploy.

---

## 11. Phase: maintenance

```bash
sudo docker compose restart        # soft restart
sudo docker compose down           # stop + remove the network (data in ./data is preserved)
```

### ⚠️ Disk cleanup — with care

```bash
sudo docker system prune -a              # safe: unused images/containers/build cache
# sudo docker system prune -a --volumes  # DANGEROUS: removes unused VOLUMES; only with human confirmation
```

> After any change to the stack (a plain restart aside), update `STACK.md` (Phase 10, invariant 0.8) before reporting done.

---

## 12. Stop signals (the agent stops and asks the human)

- A **host password** prompt (`sudo`).
- Mounting the host root (`-v /:/...`) or system paths.
- Adding the user to the `docker` group / enabling `NOPASSWD`.
- Commands that **delete data**: `prune --volumes`, `rm -rf` on a volume, `docker volume rm`.
- **Opening a port to the outside** (any `ports:` not on `127.0.0.1`; including a mode-C private IP — show it before `up`).
- Installing a VPN/private network, `tailscale up`, and other interactive auth.
- Writing to system paths (`/etc/nginx`, `/etc/letsencrypt`), `systemctl reload/restart` of system services, running `certbot`.
- Running a script/image from an **untrusted source** as root.
- **Secrets in plaintext** in the config instead of `.env`.

---

## Appendix A. What to provide in the per-stack prompt

The minimum the human specifies for a concrete stack:

- **Image and tag** (`<image:tag>`), project/container name.
- **Access mode** (A/B/C from Phase 2) and port(s).
- **Resources:** `mem_limit`, `cpus`.
- **Volumes:** what to mount and where inside the image (data path, configs).
- **Environment variables / secrets:** which ones, what goes into `.env`.
- **Healthcheck command** for this image (Appendix B).
- **Engine specifics:** process UID, required `cap_add`, custom config, memory tuning.
- **Mode B:** the domain. **Mode C:** which private network/VPN and the trusted sources.
- **Stateful?** Whether the stack holds a DB or any irreplaceable data in `./data` — so the passport records it (and it can be registered with the central backup).

> Required **output** of every deploy, not an input: a `STACK.md` passport (Phase 10, template in Appendix C).

## Appendix B. Healthchecks by engine (examples)

```yaml
# Postgres
test: [\"CMD-SHELL\", \"pg_isready -U ${DB_USER} -d ${DB_NAME}\"]

# MySQL / MariaDB  ( -h localhost = socket; $$ keeps the password out of docker inspect )
test: [\"CMD-SHELL\", \"mysqladmin ping -h localhost -u root -p\\\"$$MYSQL_ROOT_PASSWORD\\\" --silent\"]

# Redis
test: [\"CMD\", \"redis-cli\", \"ping\"]

# HTTP service (has a health endpoint)
test: [\"CMD-SHELL\", \"curl -fsS http://localhost:<port>/health || exit 1\"]

# HTTP service without curl in the image (common in alpine)
test: [\"CMD-SHELL\", \"wget -qO- http://localhost:<port>/ >/dev/null 2>&1 || exit 1\"]
```

## Appendix C. `STACK.md` passport template

Drop this in the stack root and fill it from the facts of the deploy. Half a page, facts not prose. The directive block at the top is what makes the passport self-maintaining (Phase 10, invariant 0.8) — keep it verbatim.

````markdown
# STACK PASSPORT — <project>

> **AGENT DIRECTIVE — read first, obey always.**
> This file is the authoritative description of this stack.
> Before changing the stack, read it. If your task changes ANY fact below
> (image/tag, container name, network, exposure, data layout, env, deviations),
> UPDATE this file as the final step of the task — without being asked.
> A stale passport is a bug, not a cosmetic issue.

## What this is
<one line: what the stack does> — access mode: <A | B | C>.

## Services
| container        | image:tag (pinned) | role                |
|------------------|--------------------|---------------------|
| <project>-<svc>  | <image:tag>        | <role>              |

## Network & exposure
- Network: <name> (<compose-managed | external>)
- Exposed: <none | 127.0.0.1:<port> → reverse-proxy https://<domain> | <private-ip>:<port> (mode C)>
- Reachability gotchas: <e.g. \"public at https://<domain> via system nginx, even though compose binds only 127.0.0.1\"> | none

## Data & state
- <./data/<svc>> → <what it holds>
- Stateful: <yes | no>. If yes → backup: central Borgmatic at /data/apps/backup — registered: <yes | no>

## How it was built
- Per-stack prompt: <path or link>
- Deployed: <YYYY-MM-DD>

## Operate / extend
- Common ops: <restart / logs / where config lives>
- To add <thing you anticipate>: <short pointer>

## Deviations / legacy risks
<Both kinds live here: a deliberate deviation from the docker-deploy standard taken during this
deploy, and a pre-existing violation found when an already-running box was onboarded.>
- <deviation from the standard + reason> | none
- <legacy risk found at onboarding + reason> — <accepted | should be remediated> | none
````
