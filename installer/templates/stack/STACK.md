# STACK PASSPORT — {{PROJECT}}

<!-- fraim:stub — this file is a scaffold. `/docker-deploy` Step 9 fills it in and deletes this line. -->

> **AGENT DIRECTIVE — read first, keep current.**
> This passport is authoritative for how this stack runs. Read it before any task touching the
> stack. If your change alters anything recorded here — image or tag, container name, network,
> exposure, data layout, environment, deviations — UPDATE this file in the same task, unprompted.
> A stale passport is a bug, not cosmetics.

## What this is
<one or two lines: what this stack is for, and who uses it>

## How docker is invoked here
<bare `docker`, `sudo docker`, rootless daemon, podman — as detected in Step 1>

## Services
| service | image:tag (pinned) | container name | reach mode | UID |
|---|---|---|---|---|
| <...> | <...> | <...> | <A / B / C> | <...> |

## Network & exposure
- Project network: <name> · <compose-managed | external>
- Listening: <what is bound where — loopback, private IP, the edge's 80/443>
- Edge (mode B): <none | nginx on host | Caddy | Traefik | tunnel | cloud LB> · domain: <...>
- Certificate & renewal: <how it is issued and what renews it>
- Controlled deviations: <mode C or a justified docker socket mount — and what compensates it>

## Data & state
- Data directories: <./data/... per service>
- Stateful: <yes | no>. If yes → backup: <how this stack's data is backed up> — registered: <yes | no>

## How it was built
- Workflow: `/docker-deploy` <version> · exposure: `/expose` <or "not exposed">
- Originating per-stack input: <where it is recorded>

## Operate / extend
<the two or three commands that matter here: restart, logs, where to change what>

## Deviations / legacy risks
<anything that departs from the workflow's gates, and why it was accepted. "None." if none.>
