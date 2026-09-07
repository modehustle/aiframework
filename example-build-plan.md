# Build Plan: Code Cleanup v1

## Overview
Refactor and modernize installer scripts with three independent improvements:
1. **Subtask A**: Standardize error messages across core modules
2. **Subtask B**: Add logging to dispatch operations
3. **Subtask C**: Extract shell utility functions into dedicated module

These changes touch different files → dispatch-check will verify non-overlapping paths → fleet can work in parallel.

---

## Subtask: A
**Summary**: Standardize error messages in `installer/lib/core.sh` and `installer/lib/config.sh`

### `installer/lib/core.sh`
- Replace all `die "..."` with consistent format: `die "<function>: <error>"`
- Update all error messages to use full context

### `installer/lib/config.sh`
- Align error messages with core.sh style
- Add context labels to each die() call

**Implementation**: Sed replacement + manual review of 5 patterns.

---

## Subtask: B
**Summary**: Add structured logging to dispatch operations in `installer/lib/dispatch.sh`

### `installer/lib/dispatch.sh`
- Add `_log()` function that prefixes with `[dispatch]` and timestamp
- Replace all printf stderr messages with structured logs
- Log entry/exit of each public function

### `ai/DISPATCH-LOG.md`
- Create new logging format documentation
- Example: `[dispatch] 2026-09-07T12:34:56Z dispatching build X to 3 workers`

**Implementation**: Add 10 lines of logging, update function bodies (no logic changes).

---

## Subtask: C
**Summary**: Extract common shell utilities into `installer/lib/util.sh`

### `installer/lib/util.sh`
- New file: extract `read_file()`, `join_csv()`, `parse_table()` functions used by multiple modules
- These functions are already present as inline code in config.sh, ade.sh, verbs.sh

### `installer/lib/config.sh`
- Remove inline `read_file()`, call `util.sh` version instead
- 1 line change (source instead of define)

### `installer/lib/ade.sh`
- Remove inline `parse_table()`, call util version
- 1 line change

**Implementation**: Extract, centralize, update imports (no behavior change).

---

## Validation

**dispatch-check result:**
- A: `installer/lib/core.sh`, `installer/lib/config.sh` ✓
- B: `installer/lib/dispatch.sh`, `ai/DISPATCH-LOG.md` ✓
- C: `installer/lib/util.sh`, `installer/lib/config.sh` (partial), `installer/lib/ade.sh` (partial) ⚠ 
  - Collision: config.sh and ade.sh in different subtasks
  - **Action**: Refine to make C read-only for existing modules, or merge A+C

**Decision for test**: Keep as-is. Worker C will escalate on merge conflict → this tests the conductor's review mechanism.

---

## Expected Outcome

After parallel execution + acceptance:
- Three workers complete independently in ~1 hour each (vs 3 hours sequential)
- Conductor reviews all three result.md entries in one acceptance session
- Build record includes which worker handled each change
- Lessons logged for next build (e.g., "collision in config.sh is fine if read/write split clear")
