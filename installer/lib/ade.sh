#!/bin/sh
# ade.sh — fleet execution environments: how to notice one, and what to ask it.
#
# An ADE (agent development environment) is where parallel executors actually run:
# isolated checkouts, terminals, agent sessions. It is NOT a harness — harnesses are
# where our procedures are installed, and an ADE installs nothing of ours. Its agents
# already read our skills from ~/.claude/skills and the rest, because an ADE launches
# claude, codex, omp and pi rather than replacing them.
#
# So this file is a second table next to harness.sh, not a row inside it. Adding an
# environment is adding a row — plus one branch in ade_query, because unlike a skills
# directory, a query is not a path.
#
# What we ask of an environment is fixed and small (MODES.md §9, six operations).
# What we do here is smaller still: this module only READS, and only for the watchman
# and `fraim fleet`. Nothing in it creates, dispatches or cleans up anything.
#
# The naming trap, which is why the probe is a list and not a name: on Linux a bare
# `orca` is normally the GNOME screen reader at /usr/bin/orca, and running it starts
# speech synthesis on the user's machine. Orca's own CLI is `orca-ide` there, and
# inside Orca-managed sessions the executable is named by $ORCA_CLI_COMMAND. So the
# order is: the environment variable, then the safe name, and the bare name last —
# and the bare name only where it is unambiguous.

# Columns, tab-separated:
#   key   label   env-var   binaries (space-separated, in probe order)
# The bare `orca` is deliberately absent from the Linux path; ade_cli adds it only
# when uname says this is not Linux.
ade_table() {
    cat <<'TBL'
orca	Orca	ORCA_CLI_COMMAND	orca-ide
TBL
}

# The bare binary name to try last, per key, and only off Linux.
ade_bare_name() {
    case $1 in
        orca) printf 'orca\n' ;;
        *)    return 1 ;;
    esac
}

# Resolve the executable for one environment. Prints the command word, or returns 1.
ade_cli() {
    _ade_row=$(ade_table | awk -F'\t' -v k="$1" '$1 == k { print; exit }')
    [ -n "$_ade_row" ] || return 1
    _ade_env=$(printf '%s' "$_ade_row" | cut -f3)
    _ade_bins=$(printf '%s' "$_ade_row" | cut -f4)

    # 1. What an Orca-managed session exports for itself.
    if [ -n "$_ade_env" ]; then
        eval "_ade_v=\${$_ade_env:-}"
        if [ -n "$_ade_v" ] && command -v "$_ade_v" >/dev/null 2>&1; then
            printf '%s\n' "$_ade_v"; return 0
        fi
    fi

    # 2. The unambiguous names.
    for _ade_b in $_ade_bins; do
        if command -v "$_ade_b" >/dev/null 2>&1; then printf '%s\n' "$_ade_b"; return 0; fi
    done

    # 3. The bare name, and only where it means what we think it means.
    if [ "$(uname -s 2>/dev/null)" != Linux ]; then
        _ade_bare=$(ade_bare_name "$1") || return 1
        if command -v "$_ade_bare" >/dev/null 2>&1; then printf '%s\n' "$_ade_bare"; return 0; fi
    fi
    return 1
}

# `timeout` is not POSIX, but the watchman runs on every /orient and must never hang on
# a runtime that stopped answering. Where timeout exists we use it; where it does not we
# still run the query, because refusing to look would be a worse failure than a rare stall.
ADE_TIMEOUT_S=${ADE_TIMEOUT_S:-5}
ade_timeout_bin() { command -v timeout 2>/dev/null || true; }

# Run one query against an environment. stdout is the answer, stderr is dropped, and a
# failure is an empty answer — never an exit. Callers treat "nothing" and "cannot ask"
# as the same thing on purpose: both mean we have nothing to report.
ade_query() {
    _ade_cmd=$1; shift
    _ade_to=$(ade_timeout_bin)
    if [ -n "$_ade_to" ]; then
        "$_ade_to" "$ADE_TIMEOUT_S" "$_ade_cmd" "$@" 2>/dev/null || true
    else
        "$_ade_cmd" "$@" 2>/dev/null || true
    fi
}

# Is the runtime answering at all? `status --json` is the one call every environment in
# the table documents, and the only one we make without having read a single field name.
ade_alive() {
    _ade_cmd=$1
    _out=$(ade_query "$_ade_cmd" status --json)
    [ -n "$_out" ]
}

# Emit one line per environment present on this machine: key<TAB>label<TAB>command
ade_detect() {
    ade_table | while IFS='	' read -r _k _label _env _bins; do
        [ -n "$_k" ] || continue
        _cmd=$(ade_cli "$_k") || continue
        printf '%s\t%s\t%s\n' "$_k" "$_label" "$_cmd"
    done
}

ade_present() { [ -n "$(ade_detect)" ]; }

# Scheduled prompts this environment runs against a project.
#
# We ask by PATH, not by field name. The environment's own JSON schema is not documented,
# and code written against guessed field names breaks silently on the first release that
# renames one. An absolute path either appears in the automation record or it does not,
# and that question survives any schema.
#
# The answer is two flags, not a count, and that is deliberate (D5: a finding measures the
# quantity it names). Whether the JSON arrives pretty-printed or on one line is not
# something we control, so "how many lines mention this path" is not "how many automations
# touch this project" — it only looks like it. What we can honestly say is whether any do.
#
# Prints: touched<TAB>ours   — 1/0 each. `ours` means every line that mentions the project
# also names a fraim watchman command; a scheduled watchman is layer 2 of SCHEDULING.md
# and is not a finding, while a scheduled free-form prompt is.
ade_automations() {
    _ade_cmd=$1; _ade_root=$2
    _ade_out=$(ade_query "$_ade_cmd" automations list --json)
    [ -n "$_ade_out" ] || { printf '0\t0\n'; return 0; }

    _ade_hits=$(printf '%s\n' "$_ade_out" | grep -F "$_ade_root" || true)
    [ -n "$_ade_hits" ] || { printf '0\t0\n'; return 0; }

    _ade_free=$(printf '%s\n' "$_ade_hits" | grep -v -E 'fraim +(status|sweep|doctor)' || true)
    if [ -n "$_ade_free" ]; then printf '1\t0\n'; else printf '1\t1\n'; fi
}
