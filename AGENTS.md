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

**Save as you go.** When a coherent piece is done — not at the end, a session can die —
`fraim commit <kind> "<what changed>" <path>…` over the paths you actually touched. Never
"everything": secrets, data and unfinished work do not belong in the history.

**Work happens here and now.** The task board (`ai/tasks/`) and the backlog of open
questions (`ai/backlog/`) are filled by the human only: never propose turning the work in
front of you into a task. When the human says it in words, this is what it means:

| человек говорит | это значит |
|---|---|
| «запиши задачу», «на потом», «поставь в задачи» | `/make-task` — обычная задача |
| «заведи проект», «мастер-задача», «это большая штука из многих задач» | `/make-task` — мастер-задача |
| «что у меня в задачах», «что на доске» | `fraim tasks` — пересказать |
| «возьми задачу X», «давай X из задач» | `/run-task` |
| «запиши вопрос», «в бэклог», «что в бэклоге» | `fraim backlog-new` (после его «да») / `fraim backlog` |
| «отдай дешёвому», «раздай», «через флот» | `/conductor` |
| «где мы», «что дальше» после паузы | `/orient` |
| «разберись, почему…», «реально ли X» | `/investigate` |
| «сверь документы с кодом» | `/prune` |

At the end of a piece of work, if open questions remain — important, not for now — list
them and ask which to keep; the approved ones go to `fraim backlog-new`.

If `fraim` is not installed, do the same with ordinary git and read the files whole — the
rules above are the point, the CLI is only the convenience.
<!-- fraim:end -->
