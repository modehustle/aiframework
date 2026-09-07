# Parallel Mode: First Implementation (v1)

**Status**: Implemented for testing
**Branch**: `claude/modes-open-questions-ofdv1r`
**Test date**: Ready for manual validation

---

## What was built

### 1. Dispatch Module (`installer/lib/dispatch.sh`)

**Five key functions** (MODES.md §9, the six operations):

```bash
dispatch_check()        # Verify non-overlapping file paths (§11.2 variant B)
dispatch_parse_plan()   # Extract subtasks from build plan markdown
dispatch_to_workers()   # Create worker task folders
collect_results()       # Merge worker results into build artifact
build_seal()            # Create immutable build record for conductor review
```

**What it does:**
- Reads a build plan with independent subtasks
- Checks for semantic collisions (same file touched by different workers)
- Creates worker task directories under `ai/parallel/<worker-id>/`
- Merges results into `ai/builds/<build-id>/result.md`
- Records lessons learned (empty until conductor fills in)

### 2. Example Build Plan (`example-build-plan.md`)

Three independent subtasks:
- **A**: Standardize error messages in core.sh, config.sh
- **B**: Add logging to dispatch.sh, create DISPATCH-LOG.md
- **C**: Extract utilities to installer/lib/util.sh

**Testing scenario**: C collides with both A and B on read-modify operations. This tests the conductor's merge conflict resolution on the review stage.

### 3. CLI Integration (`installer/bin/fraim`)

New command:
```bash
fraim dispatch [PLAN]
```

- Validates plan syntax
- Runs dispatch-check
- Creates worker task folders
- Reports readiness for ADE fleet execution

---

## Design Decisions (Answers to §11)

| Question | Answer | Rationale |
|----------|--------|-----------|
| 1. Experimental autonomous mode | **B** (measure tool, after A works) | No client code breaking; gather data first |
| 2. Build definition | **B** (dispatch-check as boundary) | Only way one-acceptance promise holds |
| 3. Role table location | **C** (both machine + project level) | Mechanism exists; test will show if needed |
| 4. Conductor lessons | **D** (in build journal) | Avoids premature file structure; lessons appear first in real builds |
| 5. Semantic area in plan | **B** (add field next to Files to Change) | Dispatch-check finds collisions; plan needs semantic markers |
| 6. Double checkout accounting | **C** (leave until it hurts) | No blockers for v1; sweep or registry fix later |
| 7. Ratifications | Recorded in PRINCIPLES.md D4 | "automate everything before ratification, nothing after" |

---

## How to Test

### Prerequisites
- `fraim` installed and on PATH
- Project in `ai/` structure (scaffold if needed)
- Example plan: `example-build-plan.md` at project root

### Step 1: Conductor creates the dispatch
```bash
cd /path/to/project
fraim dispatch example-build-plan.md
```

Expected output:
```
Разбор плана...
Раздача подзадач...
Worker A → /path/to/project/ai/parallel/A/task.md
Worker B → /path/to/project/ai/parallel/B/task.md
Worker C → /path/to/project/ai/parallel/C/task.md
Сборка запечатана: build-20260907-123456
Флот готов к запуску. Следующий шаг: запустить воркеров в ADE
```

### Step 2: Workers execute (simulated)
For each worker folder, an agent would:
```bash
cd ai/parallel/A
# Read task.md
# Implement changes to Files to Change
# Write result.md with summary of changes
# Commit with fraim commit
```

### Step 3: Conductor collects results
```bash
fraim dispatch:collect build-20260907-123456
```

Returns: merged `ai/builds/build-20260907-123456/result.md`

### Step 4: Conductor reviews + acceptance
```bash
# Look at merged result
cat ai/builds/build-20260907-123456/result.md

# One acceptance for the whole build (not per task)
fraim build:accept build-20260907-123456
```

### Step 5: Verify
- No merge conflicts (expected: C collides on config.sh — conductor resolves)
- All Files to Change touched exactly once per worker
- DECISIONS.md appended with one entry per worker (not overwritten)
- Build journal contains lessons for next iteration

---

## Known Gaps for v2

### 1. Actual ADE Integration
Currently: worker directories are created locally. 
Next: distribute to actual Orca instances; await async completion.

### 2. Merge Conflict Resolution
Currently: dispatch-check detects collisions; human decides.
Next: merge strategy (e.g., "C read-only in A/B context" or "split into smaller subtasks").

### 3. Semantic Markers in Plan
Currently: dispatch-check looks at Files to Change only.
Next: add `## Semantic Context` field with role boundaries (agent A vs B);
dispatcher warns if same service modified by different agents.

**Example**:
```markdown
## Subtask: A
### Semantic Context
- Modifies: PaymentService interface only
- Side effect: StripePaymentService implementation
- Safe concurrent with: Subtask B if B doesn't touch PaymentService

### `src/payment/stripe.ts`
...
```

### 4. Build Journal (§11.4)
Currently: empty placeholder in build-sealed.md.
Next: conductor fills in `## Lessons` section; becomes foundation update.

---

## Next Steps (Priority Order)

1. **Test on master session** with simple two-worker example
   - Create ai/ structure in a test project
   - Create example-build-plan.md with 2 non-overlapping subtasks
   - Run `fraim dispatch` and verify directory creation
   - Simulate worker results (hand-write result.md)
   - Collect results, verify merge

2. **Add `fraim dispatch:collect` and `fraim dispatch:accept`**
   - Collect pulls results from ai/parallel/* into build journal
   - Accept seals the build, marks for ratification

3. **Test merge conflict case**
   - Verify that overlapping paths trigger dispatch-check failure
   - Show how to refactor plan to remove collision

4. **Record ratifications in PRINCIPLES.md**
   - D4 already mentions "automate up to ratification"
   - Link to MODES.md for parallel mode specifics

5. **Plan v2: Orca integration**
   - Actually spawn worker sessions in ADE
   - Async completion tracking (poll fleet status)
   - Streaming result aggregation

---

## Files Changed

```
new:     installer/lib/dispatch.sh      Core parallel execution module
new:     example-build-plan.md          Test case: 3 independent subtasks
new:     PARALLEL-V1.md                 This document
modified: installer/bin/fraim           Added dispatch command
```

---

## Validation Checklist

- [ ] Dispatch-check rejects overlapping Files to Change
- [ ] Dispatch-check accepts non-overlapping subtasks
- [ ] Worker task directories created with correct structure
- [ ] Build record contains plan + result + lessons stub
- [ ] `fraim dispatch` command works without errors
- [ ] Master session can simulate worker results → merge → review
- [ ] No git conflicts when collecting results (unless intentional test case)

---

## Design Rationale Summary

**Why variant B (dispatch-check as boundary)?**
- Variant A (all-in-one dispatch): if humans mark the boundary, they mark it wrong; boundary has no witnesses.
- Variant B: boundary is determined by fact, not opinion — path overlap. If overlap, refactor plan.
- This is the *only* variant where "one acceptance" is honest: independent subtasks → one review conversation.

**Why build journal in §11.4 (D), not CONVENTIONS.md (B)?**
- Grounded in real builds: conductor writes lessons *after* first merge experience.
- Specific to parallel mode: a lesson about "same file, different agents" is not a code convention; it's a system lesson.
- Prevents bikeshedding: we don't know yet what lessons matter; better to collect and pattern-match later.

**Why semantic area (§11.5, B)?**
- Dispatch-check alone looks at files, not meaning.
- Scenario: Agent A moves everyone to StripePaymentService. Agent B adds PayPal to old PaymentService. Git merges both. Silent failure.
- Solution: plan field `## Semantic Context` names the service/subsystem each subtask modifies.
- Dispatcher warns: "Subtask A and B both touch Payment* — high collision risk."

---

## Questions for Next Session

1. Does example-build-plan.md test the right case (two reads + one collision)?
2. Should dispatch-check warn on read-modify collisions, or just fail on create/delete?
3. How many workers do we test with on master session — 2, 3, or 5?
4. Who decides merge strategy when dispatch-check fails — conductor, or re-plan before dispatch?
