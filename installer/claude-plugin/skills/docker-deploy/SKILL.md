---
name: docker-deploy
description: "Build and run a Docker stack securely — one isolated network, non-root containers, dropped capabilities, resource limits, healthchecks, secrets in .env — verify it on loopback, and write the STACK.md passport. Making it reachable from outside is /expose."
metadata:
  tier: capable
  version: 0.7.0
  source: fraim
---
# /docker-deploy — Build and Box a Stack

You are building **the box**: a Docker stack that runs safely on a Linux host, and the passport
that lets anyone re-enter it months later. `/bootstrap` lays the foundation of the *code*; this
workflow boxes whatever is going to run — including an off-the-shelf service that contains no
code of yours at all.

**How to read this file:** check `## GATES` before you generate anything, then follow
`## PROCEDURE` in order. Each numbered line is one action. `(why: N…)` points to the reasoning
in `## NOTES` — read a note to understand a step, not in order to perform it. `## TEMPLATES`
holds the compose skeleton and the input checklist; `## RECIPES` holds healthchecks by engine.

**Where this workflow ends.** It finishes with the stack verified on **loopback**. Letting
traffic in — reverse proxy, certificates, firewall — is **`/expose`**, and it is separate on
purpose: building a safe container is the same on every host, letting traffic in is not.
(why: N1)

> **Engine-agnostic.** Postgres, MySQL and Redis appear below as **examples**, never as a
> default service. The concrete stack (image, resources, volumes, ports, healthcheck, engine
> quirks) comes from the human — the checklist is TEMPLATE P.

> **Deterministic actions belong to `fraim`, not to you.** Where a `fraim …` command appears,
> run it rather than reproducing its effect by hand. No `fraim` — stop and say so.

## Standard layout

**The stack root is the folder you have open.** Where that folder lives on the host, on which
filesystem, and through which editor you reached it are the operator's choices, not this
workflow's business.

- One stack — one folder. Inside: `docker-compose.yml`, `.env`, `conf/`, `data/`.
- **All bind paths in compose are relative** (`./data/<service>`, `./conf/…`), so they land next
  to the compose file wherever the operator put it, and the stack stays movable.
- Never split config and data across locations, and never hardcode an absolute path "somewhere
  else". The data source is always `./data/…` relative to the stack root. This eliminates the
  class of errors where the agent picks a path of its own.

> The rule that matters is *relative paths*, not any particular directory. A workflow that names
> one is describing its author's machine, not a property of a good deployment. (why: N2)

---

## GATES

Checked always, regardless of the task. Breaking one is a failure of this workflow, not a
shortcut.

**Environment — how this machine happens to be set up**

- **G1 — Invoke docker the way this machine does.** Detect it in Step 1: rootless daemon, a user
  in the `docker` group, `sudo docker`, or `podman` behind the same CLI. Prefix every command
  accordingly. This is machine configuration, not a property of a safe deployment — do not
  "correct" the operator's setup and do not report it as a fault. (why: N2)
- **G2 — Never weaken host access to make a command work.** Adding a user to the `docker` group,
  enabling `NOPASSWD`, or relaxing file modes to get past an error is out of scope; report the
  obstacle instead. Running a privileged command you were given access to is not weakening
  anything — that is fine.

**Architecture — true wherever the stack runs**

- **G3 — One isolated network per stack.** Production containers never run on the default
  `bridge`; containers of different projects do not share a network.
- **G4 — Datastores never publish to the internet.** Postgres, MySQL, Redis, ClickHouse and
  friends are reached by service DNS name inside the project network. If another machine must
  reach one, that is `/expose` mode C — never a public port.
- **G5 — Nothing binds to `0.0.0.0`** except the 80/443 of an edge. Everything else goes to
  loopback or a private interface.
- **G6 — Processes inside containers run as non-root** (`user:` with a specific UID) wherever
  the image allows.
- **G7 — `chown` is targeted** to the specific service UID. Recursive `chown` on the stack root
  is forbidden.
- **G8 — Secrets live in `.env`**, never inline in compose. Plaintext credentials in a tracked
  file are a defect regardless of who may write it.
- **G9 — The host root and system paths are never bind-mounted** (`-v /:/…`, `/etc`, `/var/run`
  beyond an explicitly justified read-only docker socket).
- **G10 — Every stack carries `STACK.md`** in its root (Step 9). On any task touching this
  stack: read it first if it exists, create it if it does not, and update it as the final step
  whenever the change alters anything it records. A stale passport is a bug, not cosmetics.

**What still stops you — and what no longer does**

Your agent already has a permission system: it decides what you may execute and asks when it
needs to. This workflow does **not** add a second one. Run privileged commands and report what
you did; if running one was not allowed, that gate fires — it exists for exactly this. (why: N3)

So none of these stop you: a `sudo` password prompt, writing to `/etc`, `systemctl reload`,
`certbot`, `ufw`, installing a private network.

Three things still stop you, and none is about permission:

- **G11a — Architecture that breaks a gate above.** The permission gate would let you publish a
  database on `0.0.0.0`; G4 and G5 do not. Bring it to the human as a design question.
- **G11b — Irreversibility.** `prune --volumes`, `docker volume rm`, `rm -rf` on a data
  directory. Name the command and what it destroys before running it — not for permission, but
  because the human may know that volume still matters.
- **G11c — Untrusted code.** A script or image from a source you cannot verify. Show what it is
  and where it came from; trust is the human's judgement.

> *May I press this* belongs to the agent's gate. *Should this be pressed* belongs to the human.
> Asking the first question twice only trains people to click through. (why: N3)

---

## PROCEDURE

### Step 1 — Pre-flight

1.1 Establish how docker is invoked here (G1). Take the first that works and use that prefix for
    every command below; record the answer in `STACK.md` at Step 9.

```bash
docker version          # works bare: rootless daemon, or user in the docker group
sudo docker version     # otherwise
```

1.2 Read the ground you are standing on:

```bash
pwd                     # the stack root is this folder; note it, do not relocate it
df -h .                 # enough space for this stack's data?
docker compose version  # Compose v2 required (the `docker compose` subcommand)
docker network ls       # the new network name must not be taken
```

1.3 Report only what actually blocks the deploy — no space, no Compose v2, a name collision.
    A passwordless sudo, a rootless daemon and a user in the `docker` group are all normal
    setups, not findings. (why: N2)
1.4 No per-stack input from the human yet → ask for it now, using TEMPLATE P.

### Step 2 — Decide how each service will be reached

2.1 You need this before writing compose, because it determines the `ports:` block.
2.2 Choose **per service**, never once for the whole stack. (why: N4)

| Mode | Who reaches it | `ports:` in compose |
|---|---|---|
| **A. Internal** — default for datastores, caches, backends | only containers in this stack | no `ports:` at all |
| **B. HTTP on the internet** | the public, over HTTPS | `127.0.0.1:PORT:PORT` — an edge terminates TLS later |
| **C. Non-HTTP for other machines** | named machines over a private network | `${PRIVATE_IP}:PORT:PORT`, never `0.0.0.0` |

2.3 Everything that implements the choice — edges, certificates, firewalls — is `/expose`,
    after Step 8.

### Step 3 — Project network

3.1 One isolated network per independent stack (G3).
3.2 Self-contained stack → do **not** create the network by hand. The `networks:` block in
    TEMPLATE S describes it; Compose creates it on `up` and removes it on `down`.
3.3 Several independent stacks must see each other → external network, below.

### Variant for a shared network across stacks: external network

Needed **only** when several independent stacks must see each other (e.g. a shared reverse-proxy + apps in separate compose files):

```bash
docker network create <project>-shared-network
```

And in compose the network is declared external (below), otherwise Compose creates its own `<folder>_<net>` and the manually-created one stays empty.

```yaml
networks:
  <project>-net:
    external: true
    name: <project>-shared-network
```

> ⚠️ Do not mix: either Compose manages the network or `external: true`. A manual `network create` + an internal `driver: bridge` = a dangling unused network.

### Step 4 — Generate `docker-compose.yml`

4.1 Write it from TEMPLATE S, filling every placeholder from the human's input.
4.2 Check each service against this list before moving on:

- [ ] Attached to the named project network, not `bridge` (G3).
- [ ] `ports:` matches the mode chosen in Step 2 (G4, G5).
- [ ] `user: "<uid>:<gid>"` non-root, where the image allows (G6).
- [ ] `security_opt: [no-new-privileges:true]` and `cap_drop: [ALL]`.
- [ ] Resource limits (`mem_limit`, `cpus`).
- [ ] Log rotation (`logging`).
- [ ] `restart: unless-stopped`.
- [ ] `healthcheck` present; dependents use `depends_on: condition: service_healthy`.
- [ ] No `version:` field — Compose v2 ignores it.
- [ ] Secrets via `.env` (`chmod 600`), not hardcoded (G8).
- [ ] All bind paths relative.

4.3 The container fails with permission errors → **do not remove `cap_drop`**. See the caveat
    below and add back only the specific capability.

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

### Step 5 — Volume permissions

5.1 Find the process UID in the image — do not guess:

```bash
docker run --rm <image:tag> id <user>
```

5.2 `chown` **only** this service's data directory (G7):

```bash
chown -R <uid>:<gid> ./data/<service>
```

> Typical UIDs, still worth verifying live: postgres alpine = 70, postgres debian = 999,
> mysql/mariadb = 999, redis = 999, node images = 1000.

### Step 6 — Launch

6.1 Show the human the final `docker-compose.yml` and `.env` with secret values masked. This is
    a design review, not a permission request — you are asking whether the shape is right.
    (why: N5)
6.2 From the stack root:

```bash
docker compose up -d
docker compose up -d --build --force-recreate   # forced rebuild
```

### Step 7 — Post-deploy checks

```bash
docker compose ps                  # healthy?
docker compose logs -f <service>   # started without permission errors
docker stats                       # resources within limits
```

7.1 Then the security check — nothing beyond what Step 2 decided may be listening:

```bash
docker compose ps --format '{{.Service}} -> {{.Ports}}'
ss -tlnp | grep -v '127.0.0.1'
```

7.2 Anything unexpected in that output → fix the compose and repeat, before going further.
    (why: N6)

### Step 8 — Make it reachable

8.1 Mode A services are done — reached by service DNS name on the project network.
8.2 Mode B or C → run **`/expose`**. It takes the verified stack the rest of the way and records
    the result in `STACK.md`.

### Step 9 — The passport

9.1 The deploy is not done until the stack has `STACK.md` in its root (G10). It is the
    **re-entry document**: what a human or an agent reads weeks later instead of
    reverse-engineering compose and `.env` again. (why: N7)
9.2 Create it: `fraim stack-passport`. It writes the template, including the standing directive
    that keeps the passport current.
9.3 Fill it from the facts established during this deploy: how docker is invoked here, images
    and pinned tags, network, exposure per service, data directories, deviations, and the
    originating per-stack input. Roughly half a page — a fixed-schema fact sheet, not a wiki.
9.4 Show it to the human together with the rest of the deploy.
9.5 Save the point, naming the paths this deploy actually wrote:
    `fraim commit deploy "<project> — <one line>" docker-compose.yml STACK.md conf`.
    Never `.env` — it holds the secrets, and the verb has no \"everything\" argument on purpose.

### Step 10 — Maintenance

```bash
docker compose restart        # soft restart
docker compose down           # stop + remove the network (data in ./data is preserved)
docker system prune -a        # safe: unused images, containers, build cache
```

10.1 `docker system prune -a --volumes` **destroys unused volumes irreversibly**. Name what it
     will delete before running it (G11b).
10.2 After any change beyond a plain restart, update `STACK.md` before reporting done (G10).

---

## TEMPLATES

### TEMPLATE S — `docker-compose.yml`

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
    user: \"<uid>:<gid>\"            # non-root. Find UID: docker run --rm <image> id <user>
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
      - ./data/<service>:<data path inside the image>      # relative → lands next to the compose file
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

### TEMPLATE P — what the human provides for a concrete stack

- **Image and tag** (`<image:tag>`), project and container name.
- **Reach mode** per service (A/B/C from Step 2) and port(s).
- **Resources:** `mem_limit`, `cpus`.
- **Volumes:** what to mount and where inside the image — data path, configs.
- **Environment variables and secrets:** which ones, what goes into `.env`.
- **Healthcheck command** for this image — see RECIPES.
- **Engine specifics:** process UID, required `cap_add`, custom config, memory tuning.
- **Mode B:** the domain. **Mode C:** which private network and the trusted sources.
- **Stateful?** Whether the stack holds a database or any irreplaceable data in `./data`, so the
  passport records it and it can be registered with whatever backup this operator runs.

> `STACK.md` is the required **output** of every deploy, not an input (Step 9).

---

## RECIPES

### Healthchecks by engine (examples)

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

---

## NOTES

**N1 — Why exposure is a separate workflow.** Building a safe container is the same on every
host: the same network isolation, the same non-root user, the same dropped capabilities. Letting
traffic in is not — it depends on which edge the host runs, which ACME flow, which firewall. Kept
in one file, that variability leaked into the whole playbook and made a universal document read
as one server's story. Split, each half can be honest: this one has no environment-specific
content left, and `/expose` is explicitly a menu of recipes with no default.

**N2 — Why the machine's setup is never a finding.** This workflow used to open by asserting that
docker runs through `sudo` and the user is not in the `docker` group, and to instruct the agent
to report a passwordless sudo as a warning. That made the most common setup in the industry look
like a misconfiguration. How docker is invoked is configuration the operator chose; what makes a
deployment safe is G3–G10, and those hold regardless. Keeping the two apart is the point — the
security gates lost nothing when the environment assumptions went.

**N3 — Why there is no second permission gate.** Every harness already ships one: Claude Code
prompts before a shell command, Codex runs read-only by default. A workflow that also asks means
the human answers the same question twice, and the reliable effect of asking twice is that people
stop reading either prompt. What survives is the three cases that were never about permission —
architecture, irreversibility, trust — because no permission system has an opinion about those.

**N4 — Why the reach mode is per service.** The common failure is a stack where the web UI
legitimately needs mode B and the database silently inherits it, because the decision was taken
once for the whole compose file. G4 exists because that mistake is cheap to make and expensive to
find.

**N5 — Why the pre-launch review is not a permission request.** You are not asking whether you
may run `up`; your agent's gate settles that. You are asking a human to look at the shape of what
is about to run — the ports, the mounts, the masked secrets — while it is still cheap to change.
That is the same kind of stop as `/prune` proposing a diff: a judgement, not an authorisation.

**N6 — Why `ss -tlnp` beats the compose file.** The compose file states intent; `ss` states
reality. Docker writes iptables rules of its own, an image can publish a port you did not ask
for, and a stale container from an earlier attempt can still hold a binding. Reading the
listeners is the only check that answers what is actually exposed.

**N7 — Why the passport belongs to deploy, not to bootstrap.** Every box gets one, including a
pure off-the-shelf service that holds none of your own code — and for such a service the passport
*is* the entire re-entry story. A project that also contains source code gets the richer
foundation from `/bootstrap`, but that is about the *code*; `STACK.md` is about the *box*: image,
network, exposure, data. Complementary layers, never duplicates.
