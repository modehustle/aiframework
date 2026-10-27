---
created: 2026-10-27
from: system-structure-modernization
---
# A separate interface for the operator

## Question
What should a dedicated interface for the human look like — a place to see the board, projects, the
backlog, decisions and the state of every project intuitively, instead of terminal commands and the
menu? Where does it live, what does it read, and what (if anything) may it change?

## Why it matters
The operator works only through the agent and almost never types CLI commands; the current menu and
terminal output are not a comfortable way to look at the system. The gardener (/prune) and the drift
signals also need a visible home, otherwise they go unused.
