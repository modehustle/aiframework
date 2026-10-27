---
created: 2026-10-27
from: system-structure-modernization
---
# Operator messages in a locale catalog

## Question
How should the operator's messages (errors, refusals, the watchman's verdict, `fraim help`, the
menu) move out of the code into a message catalog (`locale/ru`) so other languages can be added:
where the strings live, how keys are named, how the language is chosen, what happens when a
translation is missing, and how tests check output without depending on one language.

## Why it matters
The product is English inside, but several hundred Russian operator strings are still hardcoded
across the CLI. Two lines of the build journal also come from these messages. Until the catalog
exists, no second language is possible and every new verb adds more hardcoded Russian.
