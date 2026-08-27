#!/bin/sh
# skills.sh — turn procedures/ into Agent Skills directories.
#
# One procedure becomes one skill directory holding exactly one file:
#   <name>/SKILL.md
# The single-file rule is not tidiness, it is a compatibility constraint.
# Hermes installing a skill from a URL fetches only SKILL.md and drops
# references/ and scripts/ alongside it; omp discovers skills one level deep,
# non-recursively. A procedure split across supporting files would arrive
# broken in both. See HARNESS_TARGETS.md.

# Escape a value for a double-quoted YAML scalar. Descriptions are always
# quoted: they contain colons, and an unquoted scalar with ": " in it parses
# as a nested mapping and fails.
yaml_dq() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Canonical build output. Harness targets are copies of this tree.
fraim_build_dir() { printf '%s/skills\n' "$FRAIM_HOME"; }

# Render one procedure into a SKILL.md on stdout.
# The procedure body is copied verbatim; only the frontmatter is rewritten,
# so the text an agent reads is exactly the text under version control.
skill_render() {
    _name=$1
    _src=$(fraim_procedure_file "$_name") || die "нет такой процедуры: $_name"
    _ver=$(fraim_version)
    _desc=$(fm_get "$_src" description)
    _tier=$(fm_get "$_src" tier)

    printf '%s\n' "---"
    printf 'name: %s\n' "$_name"
    printf 'description: "%s"\n' "$(yaml_dq "$_desc")"
    printf '%s\n' "metadata:"
    printf '  tier: %s\n' "$_tier"
    printf '  version: %s\n' "$_ver"
    printf '  source: fraim\n'
    printf '%s\n' "---"
    # Strip the source frontmatter; keep everything after it byte for byte.
    awk 'NR==1 && $0=="---" { infm=1; next } infm && $0=="---" { infm=0; next } !infm' "$_src"
}

# Build every skill into the canonical tree. Rebuilt from scratch each time so
# a procedure deleted upstream does not linger as a stale skill.
skills_build() {
    _out=$(fraim_build_dir)
    rm -rf "$_out"
    mkdir -p "$_out"
    fraim_procedures | while read -r _n; do
        mkdir -p "$_out/$_n"
        skill_render "$_n" > "$_out/$_n/SKILL.md"
    done
    mkdir -p "$_out/$FRAIM_NAME"
    master_render > "$_out/$FRAIM_NAME/SKILL.md"
    printf '%s\n' "$_out"
}

# The master skill: a routing table, not a retelling of the system.
# It triggers on orientation questions ("where did I stop", "what needs
# attention"), which is the one moment an agent needs cross-project state.
master_render() {
    _ver=$(fraim_version)
    cat <<SKILLEOF
---
name: $FRAIM_NAME
description: Control panel for the fraim workflow system. Use when the user asks where a project stands, what needs attention, what to do next, which projects have drifted, or how to install and update the workflow procedures. Routes to the right procedure and reads the deterministic project watchman.
metadata:
  version: $_ver
  source: fraim
---
# fraim — control panel

\`fraim\` keeps a project's context durable across chats and weeks. Each project
carries a **foundation** (\`ARCHITECTURE.md\`, \`CONVENTIONS.md\`, \`DECISIONS.md\`,
\`ai/\`) and work moves through explicit procedures instead of improvisation.

**Invariant 0.4** — the foundation is read FIRST before any task and updated LAST
after it. \`DECISIONS.md\` is append-only. A stale foundation is a bug, not cosmetics.

## When the user asks "where do things stand"

Run the watchman. It is deterministic — file reads, \`git log\` and mtimes, no model,
no network — so it is free to call every time.

\`\`\`sh
fraim status          # human-readable verdict for the current project
fraim status --json   # same verdict, machine-readable
\`\`\`

Exit codes: \`0\` healthy · \`1\` something needs the human · \`2\` project is not
under the system.

Report the verdict as-is. **Do not act on it** — name the procedure the user should
run and stop there. Every mutating procedure in this system ends by asking the human,
by design.

## Routing table

| The user wants | Procedure | Model tier |
|---|---|---|
| decide what to build, before any code exists | \`/design-session\` | strong |
| lay the foundation of a new authored project | \`/bootstrap\` | strong |
| box a stack in Docker and write its passport | \`/docker-deploy\` | capable |
| plan an agreed feature for a fresh-chat executor | \`/make-task\` | strong |
| execute a prepared plan from the queue | \`/run-task\` | cheap |
| repair a plan the executor called defective | \`/revise-task\` | strong |
| close a run that drifted into live debugging | \`/reconcile-task\` | capable |
| a one-file micro-fix, no ceremony | \`/hotfix\` | capable |
| find out where a bug is, or whether X is feasible | \`/investigate\` | strong |
| reconcile the foundation with reality | \`/prune\` | strong |
| re-enter a project after a break | \`/orient\` | any |
| bring an existing project under the system | \`/onboard\` | strong |

The procedures are separate skills — invoke them by name. This skill does not
contain their text and must not paraphrase it.

## Other commands

| Command | What it does |
|---|---|
| \`fraim init\` | install / update / pick up a newly installed harness |
| \`fraim projects\` | list, add or remove projects in the registry |
| \`fraim doctor\` | what is installed where, which version, what diverged |
| \`fraim show NAME\` | print a procedure's text (for environments without skills) |

## The one rule for you

The watchman notices; the human decides. Never run \`/prune\`, \`/run-task\` or
\`/hotfix\` because the status output suggested them — surface the line and wait.
SKILLEOF
}

# Generated manifest. Nothing in this repo reads it — the frontmatter is the
# source of truth — but it exists as the declared interchange artifact for
# future non-shell generators and for CI.
manifest_render() {
    printf '{\n  "version": "%s",\n  "procedures": [\n' "$(fraim_version)"
    _first=1
    fraim_procedures | while read -r _n; do
        _f=$(fraim_procedure_file "$_n")
        _d=$(fm_get "$_f" description | sed 's/\\/\\\\/g; s/"/\\"/g')
        _t=$(fm_get "$_f" tier)
        _o=$(fm_get "$_f" order)
        [ "$_first" = 1 ] || printf ',\n'
        _first=0
        printf '    { "name": "%s", "file": "procedures/%s.md", "tier": "%s", "order": %s, "description": "%s" }' \
            "$_n" "$_n" "$_t" "$_o" "$_d"
    done
    printf '\n  ]\n}\n'
}
