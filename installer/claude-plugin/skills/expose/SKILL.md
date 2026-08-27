---
name: expose
description: "Decide and implement how a running service is reachable from outside — internal only, HTTP on the internet behind a reverse proxy with TLS, or non-HTTP over a private network — then apply the edge and firewall for whichever tooling this host actually uses."
metadata:
  tier: capable
  version: 0.4.0
  source: fraim
---
# /expose — Reach a Service From Outside

You are deciding, and then implementing, **how this service is reachable**. The stack is already
built and running on loopback (`/docker-deploy`, Phase 8 verified it). This workflow takes it
from "runs on this host" to "reachable by whoever should reach it, and nobody else".

This is a separate workflow because it is the one part of deployment where **environments
genuinely differ**. How you build a safe container is the same everywhere. How traffic gets in
depends on the edge this host runs — nginx, Caddy, Traefik, a tunnel, a cloud load balancer —
and on the firewall it uses. So the decision is made explicitly here, and the recipes are
per-target. **There is no default edge in this workflow, because there is no default host.**

> **Deterministic actions belong to `fraim`, not to you.** Where a command `fraim …` appears,
> run it rather than reproducing its effect by hand. No `fraim` — stop and say so.

> Paths are **repo-relative to the project root** (the folder the agent has open). Never
> hardcode an absolute project path.

---

## GATES

Check these before starting and hold them throughout.

- **G1 — Nothing lands on `0.0.0.0`** except the ports of the edge itself (usually 80/443).
  Application ports bind to loopback or to a private interface. This is invariant 5 of
  `/docker-deploy`, and this workflow is where it is most tempting to break.
- **G2 — Datastores are never reachable from the internet.** A public database port is found
  by scanners in hours. If another machine must reach it, that is mode C, never a public port.
- **G3 — Never invent an identity.** The domain, the email for the certificate, and consent to
  a CA's terms come from the human. Do not guess a domain, do not accept ToS on their behalf.
- **G4 — Never weaken host access to get past an error.** Report the obstacle instead.
- **G5 — You apply and report.** Writing to the edge's config, reloading it, issuing a
  certificate and opening a firewall port are ordinary privileged commands. Your agent's own
  permission gate decides whether you may run them; this workflow does not ask a second time.
  (why: N1)
- **G6 — One service, one decision.** A stack with three published services has three separate
  mode choices. Do not apply one mode to the whole stack by default.

---

## PROCEDURE

### Step 1 — Choose the mode, per service

1.1 List every service in the stack the human wants reachable, and by **whom**.
1.2 For each, pick exactly one mode. (why: N2)

| Mode | Who needs to reach it | `ports:` in compose |
|---|---|---|
| **A. Internal** — the default for datastores, caches, queues, backends | only other containers in this stack | no `ports:` at all; reached by the service's DNS name on the project network |
| **B. HTTP on the internet** — web UI or API | anyone on the internet, over HTTPS | `127.0.0.1:PORT:PORT`, then an edge terminates TLS (Step 3) |
| **C. Non-HTTP for other machines** — a database reached by another server, or by you from a laptop | named machines, not the public | `PRIVATE_IP:PORT:PORT` — a private interface only, never `0.0.0.0` (Step 4) |

1.3 A service you cannot place in a mode → ask. Do not default to B because it is the easiest.
1.4 Mode A → nothing to do here. Skip to Step 6.

### Step 2 — Establish what this host already runs

2.1 Do not install an edge before checking which one is already there. (why: N3)

```bash
# Which edge, if any, is already serving this host
command -v nginx caddy traefik 2>/dev/null
docker ps --format '{{.Names}}\t{{.Image}}' | grep -Ei 'nginx|caddy|traefik|tunnel'
ss -tlnp | grep -E ':(80|443)\b'

# Which firewall is in charge
command -v ufw firewall-cmd nft iptables 2>/dev/null
```

2.2 An edge is already serving 80/443 → **use it**. Adding a second one to the same ports
    cannot work and will take the first one down.
2.3 Nothing is serving 80/443 and the host sits behind a cloud load balancer or a tunnel →
    the edge lives outside this host; the recipe is R5 or R6.
2.4 Nothing at all → pick with the human from `## RECIPES`, do not decide alone. (why: N3)

### Step 3 — Mode B: put the service behind the edge

3.1 Confirm the domain resolves to this host, and that the human gave you the domain:
    `dig +short <domain> A`.
3.2 Open the edge's ports in whichever firewall Step 2 found — recipe F1–F4.
3.3 Apply the recipe for the edge from `## RECIPES` — R1–R6.
3.4 Keep the generated config **in the project repo** (`./deploy/<edge>/`), then place it where
    the edge reads it. The repo copy is what survives a host rebuild. (why: N4)
3.5 The certificate: any ACME flow needs an email and ToS consent from the human (G3).
3.6 Never leave the service reachable on plain HTTP once TLS works — the edge must redirect.

### Step 4 — Mode C: private network only

4.1 Choose the private path with the human: a cloud provider's private network (all
    participants in one project), or a VPN mesh such as Tailscale or WireGuard (clients roam,
    each device keeps a stable address wherever it is).
4.2 Installing it needs interactive auth — `tailscale up` prints a login URL. Run it and hand
    the human the URL to finish in a browser.
4.3 Publish the port on the private address only: `PRIVATE_IP=<address>` in `.env`, and
    `${PRIVATE_IP}:PORT:PORT` in compose.
4.4 Add the firewall as defence in depth — recipe F1–F4. The binding is the real control; the
    firewall is the second layer. (why: N5)
4.5 Mode C is a **controlled deviation** from G1/G2: it is compensated by the port never being
    visible from the internet. Say so explicitly, and record it in `STACK.md` (Step 6).

### Step 5 — Verify from the outside, not from the inside

5.1 `ss -tlnp` — the listener is where you intended, and nothing else appeared.
5.2 Mode B: `curl -I http://<domain>` expects a redirect; `curl -I https://<domain>` expects
    the app. Check the certificate chain, not only that the page loads.
5.3 Mode C: reach the port **from another machine** on the private network, and confirm it is
    refused from a public address. A test that only runs on the host proves nothing. (why: N6)
5.4 Confirm automatic certificate renewal is actually scheduled — the timer, cron entry, or the
    edge's built-in renewal. A certificate nobody renews expires in 90 days. (why: N7)
5.5 Anything reachable that should not be → fix it now, before Step 6.

### Step 6 — Record it in the passport

6.1 `STACK.md` records exposure: mode per service, the edge, the domain, which ports are open
    and on which interface, and any controlled deviation from Step 4.5.
6.2 No `STACK.md` yet → `fraim stack-passport` creates it from the template; fill the
    `## Network & exposure` section.
6.3 Save the point, naming the paths: `fraim commit deploy "expose <service> — mode <A|B|C>"
    STACK.md docker-compose.yml`. Host-level files (`/etc/...`) are not in the repository and are
    not saved by this — that is what the passport records instead.

---

## RECIPES

Pick by what Step 2 found. Each is a sketch to adapt, not a script to paste blindly.

### R1 — nginx already on the host

```bash
# the config lives in the repo first
cp ./deploy/nginx/<domain>.conf /etc/nginx/sites-available/<domain>.conf
ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
certbot --nginx -d <domain> -m <email from the human> --agree-tos
```

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name <domain>;
    client_max_body_size 25m;          # tune to the app

    location / {
        proxy_pass http://127.0.0.1:<port>;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade           $http_upgrade;      # WebSocket, if needed
        proxy_set_header Connection        "upgrade";
        proxy_read_timeout 60s;
    }
}
```

`certbot --nginx` adds the 443 block and the 80→443 redirect itself. For full control over the
config, `certbot certonly` issues only the certificate and you write the 443 block yourself.

### R2 — Caddy

Obtains and renews certificates on its own; there is no certbot step and no redirect to write.

```caddyfile
<domain> {
    reverse_proxy 127.0.0.1:<port>
}
```

```bash
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```

### R3 — Traefik in a container

Routing is declared as labels on the service being exposed, so it lives in the same compose
file as the app. Traefik needs the docker socket read-only — that is the one justified
exception to invariant 9 of `/docker-deploy`, and it is worth stating in `STACK.md`.

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<name>.rule=Host(`<domain>`)"
  - "traefik.http.routers.<name>.entrypoints=websecure"
  - "traefik.http.routers.<name>.tls.certresolver=<resolver>"
  - "traefik.http.services.<name>.loadbalancer.server.port=<container port>"
```

With Traefik the app needs **no** `ports:` block at all — it is reached over the project
network, which is strictly better than binding to loopback.

### R4 — nginx in a container

The same config as R1, but mounted into the container and sharing the project network, so
`proxy_pass` targets the service DNS name rather than `127.0.0.1`. The certificate is usually
handled by a companion ACME container. Choose this when the host must stay stateless.

### R5 — a tunnel (Cloudflare Tunnel and similar)

No inbound ports at all: an outbound agent connects to the provider, which routes the domain.
The firewall keeps denying all inbound — that is the point. Suited to a host with no public IP,
or one you do not want to expose. The provider becomes part of your trust boundary; say so in
`STACK.md`.

### R6 — a cloud load balancer

TLS terminates outside this host. The host publishes on a private interface reachable by the
balancer, and the provider's security group is the firewall — recipe F4. Do **not** also open
the port with a host firewall "to be safe": two controls that disagree are how a port ends up
open by accident.

### F1 — ufw

```bash
ufw allow 80/tcp && ufw allow 443/tcp           # mode B: the edge only
ufw deny <port>                                  # mode C: deny on the public interface
ufw route allow proto tcp from <private_subnet> to any port <port>
ufw reload && ss -tlnp | grep <port>
```

Docker publishes ports by writing iptables rules directly and bypasses ufw. If any container
binds anywhere other than loopback, install `ufw-docker` first — verify the source before
running it, since an unverified script from the internet is exactly the untrusted-code case
G5 does not cover. (why: N8)

### F2 — firewalld

```bash
firewall-cmd --permanent --add-service=http --add-service=https
firewall-cmd --permanent --zone=trusted --add-source=<private_subnet>   # mode C
firewall-cmd --reload && firewall-cmd --list-all
```

### F3 — nftables directly

```bash
nft list ruleset                       # read what is there before adding
```

Add rules into the existing chain structure rather than replacing the ruleset — on most
distributions something else is already managing it, and a wholesale replace silently drops
its rules.

### F4 — cloud security groups

The firewall lives in the provider's console or API, not on the host. Generate the intended
rule set, show it to the human, and let them apply it — you generally do not hold provider
credentials, and where you do, this is exactly the irreversible-change case from
`/docker-deploy` §12.

---

## NOTES

**N1 — Why this workflow does not ask permission.** Your agent already has a permission system
that decides what you may execute and asks when it needs to. A second gate on top means the
human answers the same question twice, which trains them to click through both. Run the command
and report what you did. What still stops you is listed in `/docker-deploy` §12, and none of it
is about permission: architecture that breaks an invariant, irreversibility, untrusted code.

**N2 — Why the mode is chosen per service, not per stack.** The common failure is a stack where
the web UI legitimately needs mode B and the database quietly inherits it, because the decision
was made once for the whole compose file. G2 exists because that mistake is cheap to make and
expensive to discover.

**N3 — Why you check for an existing edge first.** Two processes cannot both listen on 443. An
agent that installs its preferred proxy onto a host that already had one takes down every other
site on that host. This is also why this workflow has no default edge: the right answer is
whatever this host already runs, and only when there is nothing does it become a choice — a
choice with long consequences, so the human makes it.

**N4 — Why the config lives in the repo first.** A config that exists only in `/etc` is
invisible to `/prune`, absent from git, and gone when the host is rebuilt. Keeping the source of
truth in the project and copying it out means the exposure is reviewable in a diff like
everything else.

**N5 — Why the binding matters more than the firewall.** A firewall rule is a second opinion
about traffic that already arrived. A port bound to a private address was never reachable in the
first place. When the two disagree the binding wins — so get the binding right and treat the
firewall as depth, not as the control.

**N6 — Why verification runs from another machine.** `curl localhost` succeeds regardless of how
wrong the exposure is. The question this workflow answers is what the *outside* can reach, and
only the outside can answer it.

**N7 — Why renewal is verified, not assumed.** Certificate expiry is the single most common way
a working deployment breaks months later with no change made to it. The renewal timer is part of
the deploy, not an afterthought — and `fraim status` cannot see it, because it lives on the host
rather than in the repository.

**N8 — Why docker and host firewalls disagree.** Docker inserts its own iptables rules ahead of
the ones ufw manages, so a published port can be reachable from the internet while `ufw status`
sincerely reports that it is denied. Believing the firewall over `ss -tlnp` is how a database
ends up public.
