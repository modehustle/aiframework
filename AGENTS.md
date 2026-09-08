<!-- fraim:begin — managed by `fraim init`, do not edit inside -->
## Project foundation

This project keeps a persistent foundation. Read it before you change anything, and update
it as the last step of your change — without being asked.

- `ARCHITECTURE.md` — what this project is: components, data model, interfaces.
- `CONVENTIONS.md` — the house rules, plus `## Known Pitfalls / Lessons`.
- `DECISIONS.md` — the decision log. **Append-only**, newest on top; never rewrite or
  delete an entry. If a decision is superseded, add the new one saying so.
- `ai/` — the working folder: task queue, archive, investigations.
- `STACK.md` — the deploy passport, if this project is packaged.

**The golden rule.** `ARCHITECTURE.md` and `CONVENTIONS.md` are read FIRST, before any task,
and updated LAST, after it. A stale foundation is a bug, not cosmetics. If your change made
the map wrong, fixing the map is part of the change, not follow-up work.

**Behaviour changed → one line in `DECISIONS.md`.** A change to what the program does, with
no trail anywhere, is not allowed. Pure cosmetics (a comment, a log string, formatting) need
no entry.

**Something bit you → one line in `## Known Pitfalls / Lessons`** (in `CONVENTIONS.md`). Only
the kind of surprise that would trap the next change too — something that fails silently,
reads as the opposite of what it does, or must happen in an order nobody would guess. Propose
the line, let the human approve, edit or skip it, then save it with the change. A lesson that
stays in the chat is paid for twice.

**Save as you go.** When a coherent piece is done, put down a save point naming the paths you
changed — not at the end of the session, a session can die. Save the paths you actually
touched, never "everything": secrets, data and unfinished work do not belong in the history.

If the `fraim` CLI is on PATH, it does the mechanical half:

```sh
fraim status                                  # deterministic verdict on this project
fraim commit <kind> "<what changed>" <path>…  # a save point over the named paths
```

If it is not installed, do the same with ordinary git — the rules above are the point, the
CLI is only the convenience.
<!-- fraim:end -->
