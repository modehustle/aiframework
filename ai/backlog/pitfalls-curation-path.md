---
created: 2026-10-31
from: fleet-audit-new-harnesses
---
# A sanctioned way to curate the lessons

## Question
How should a stale or broken line of `## Known Pitfalls / Lessons` be removed or rewritten? `/prune`
tells the agent to rewrite each approved section with `fraim arch`, but `fraim arch` refuses that
section («lessons are added as a line: fraim pitfall»), and `fraim pitfall` only appends. Should
there be a verb that drops or replaces one lesson by its text, should `fraim arch` accept that
section when `/prune` applies what the human approved, or should `/prune` say plainly that curating
lessons is a hand edit?

## Why it matters
On 2026-10-31 five lessons described code that no longer existed and one had been split in two by a
stray newline; the only way to fix them was a hand edit of the foundation, which the house rules
reserve for the verbs. Without a sanctioned path, stale lessons stay — and every session reads them
first — or get edited by hand in a different way each time.
