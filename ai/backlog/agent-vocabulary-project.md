---
created: 2026-10-28
from: task-queue-master-logic
---
# One word for a project in what the agent reads

## Question
Which term should carry the meaning of a multi-task undertaking in everything the agent reads —
«project» or «master task» — and should the other be dropped or kept only as an alias? Today the
intent table says «a project», /make-task and /run-task say «master task (project)», the verb flag
is `--master`, and the board prints `◆`. A cheap model asked for a «проектная задача» did not
connect it with `--master`.

## Why it matters
The kind is now required and a project is laid down with its subtasks, but the agent still has to
map the human's word onto the right kind. Two names for one thing across the intent table,
procedures, verb flags and CLI output make that mapping a guess for weaker models. Changing it
touches the procedures, the verb table, the flag names and the operator's output, so it is a
product decision, not a wording fix.
