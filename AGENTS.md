<!-- fraim:begin — managed by `fraim init`, do not edit inside -->
## Project foundation

This project keeps a persistent foundation. Read it before you change anything, and update
it as the last step of your change — without being asked.

**Start every session with `fraim brief`.** It prints the whole foundation in one stream —
the map (`ARCHITECTURE.md`), the house rules with `## Known Pitfalls / Lessons`
(`CONVENTIONS.md`), the living decisions (`DECISIONS.md`), `STACK.md` if there is one, the
task board — and, first, the list of verbs this CLI has. It ends with a mark that nothing
was cut. Do not read those files with a line limit instead. To look something up:
`fraim find` with 2–4 keys, in both languages and as word stems (`кэш cache`) — it returns
whole entries.

**The golden rule.** The foundation is read FIRST and updated LAST. A stale foundation is a
bug, not cosmetics. If your change made the map wrong, fixing the map is part of the change.

**Write the foundation through the verbs, not by hand.** The text is yours; place, format
and line wrapping are theirs:

- the map changed → `fraim arch "<section>"` (body on stdin) rewrites that one section;
- behaviour changed → `fraim decide "<title>"` (body on stdin), newest on top; replacing an
  earlier decision → `--supersedes "<its heading>"`, and the old entry moves to the archive.
  Pure cosmetics (a comment, a log string, formatting) need no entry;
- something bit you that would trap the next change too — fails silently, reads as the
  opposite of what it does, must happen in an order nobody would guess → propose one line,
  and on the human's yes `fraim pitfall "<line>"`.

**English inside.** Everything you write into the project — the foundation, task cards,
backlog questions, commit messages, code comments — is English, whatever language you speak
with the human. The verbs check it and refuse another language; a name or the human's own
words in another language go in quotes («…») or backticks.

**Save as you go.** When a coherent piece is done — not at the end, a session can die —
`fraim commit <kind> "<what changed>" <path>…` over the paths you actually touched. Never
"everything": secrets, data and unfinished work do not belong in the history.

**Work happens here and now.** The task board (`ai/tasks/`) and the backlog of open
questions (`ai/backlog/`) are filled by the human only: never propose turning the work in
front of you into a task. The human speaks in words, not commands — recognise the intent:

| The human's intent | What it means |
|---|---|
| set work aside to do later, not now | `/make-task` — an ordinary task |
| start something large that will take several tasks (a project) | `/make-task` — a master task |
| know what is pending, planned or in progress | `fraim tasks` — report it |
| work on a specific task from the board | `/run-task` |
| keep an open question without acting on it | `fraim backlog-new` after the human confirms / `fraim backlog` to review |
| have work done by cheaper models, or split into parallel directions | `/conductor` |
| get back into the project after a break | `/orient` |
| understand a behaviour nobody can explain, or check that something is feasible | `/investigate` |
| bring the documents back in line with the code | `/prune` |

Judge the intent, in whatever language and wording it comes. Anything else the human asks for is work to do now, in this session. Unsure whether they mean now or later — do it now, or ask one question.

At the end of a piece of work, if open questions remain — important, not for now — list
them and ask which to keep; the approved ones go to `fraim backlog-new`.

If `fraim` is not installed, do the same with ordinary git and read the files whole — the
rules above are the point, the CLI is only the convenience.
<!-- fraim:end -->
