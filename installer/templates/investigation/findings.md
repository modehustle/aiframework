# INVESTIGATION — {{SLUG}}

<!-- fraim:stub — /investigate заполняет разделы ниже и удаляет эту строку. -->

## Baseline / provenance
{{PROVENANCE}}

## Investigation goal
<the ONE unclear thing, as a question that can be answered>

## Hypothesis register
| # | Hypothesis | Status | Evidence |
|---|---|---|---|
| 1 | <hypothesis> | open / confirmed / excluded | <what was observed> |

## Diagnostic actions
- <what was run or instrumented, and what it showed>

## Outcome — fill exactly ONE branch

### DIAGNOSIS
<root cause, plainly. Route: reactive fix (surgical) | /make-task (structural) | /revise-task | /prune.>

### DEAD-END
<what was ruled out, where exactly you got stuck, what the human must decide or provide.>

## Touched / created manifest — REPO
<every repo file created or modified during the investigation — this is the cleanup list>

## State manifest — WORLD
<baseline first: what the slice looked like before — row count, leases, worker state>
<then every world-state mutation with its undo command, written live, the moment you mutate>

## Restored to baseline
<repo: what `git status` shows — and world: what was undone, counted against the baseline above>
