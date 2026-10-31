---
created: 2026-10-31
from: fleet-audit-new-harnesses
---
# Other harnesses as fleet workers

## Question
Should a round be able to run workers in a harness other than the conductor's — through each
harness's headless run (`claude -p`, `codex exec`, `opencode run`…) or through ACP with `acpx` — and
if so, how does the conductor choose a harness for a subtask without the fragile «own subagents or
another harness» decision the owner set aside on 2026-10-31?

## Why it matters
Today the workers are the conductor's own subagents, so a round stays within one vendor's models and
dies with the conductor's session. AUDIT-FLEET-HARNESSES.md maps what the 28 harnesses offer: 25 run
headless with the model in argv, 23 speak ACP, and `acpx` already knows how to launch 17 of them.
Workers from other harnesses would bring cheaper models and outlive the session, at the cost of a
launch table to keep current and unattended permission flags on the user's machine.
