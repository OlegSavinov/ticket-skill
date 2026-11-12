# Lesson ledger

Files in `.claude/ticket/` (git-excluded locally, never committed):

| File | What |
|---|---|
| `lessons.yml` | lessons, one entry each (schema below) |
| `checks.yml` | promoted lessons the edit hook enforces on changed lines |
| `log.yml` | one metrics entry per closed ticket |
| `run.jsonl` | the open ticket's caught-error events (written by the hooks and `L event`) |
| `state.json` | the open ticket (key, base commit, stop-hook counters) |

## Lesson schema

```yaml
- id: L-014                 # next id = highest + 1
  lesson: "Order cancellation goes through OrderV2#cancel!, never Order#cancel"
  cause: explore_miss       # from the cause table
  cause_note: "found Order first, never searched for V2/legacy variants"
  fix: lesson               # where the fix lives: lesson | check | skill | template
  area: app/models          # path prefix it applies to; omit for repo-wide
  refs: [app/models/order_v2.rb, "OrderV2#cancel!"]   # paths or Const / Const#method
  seen: [PROJ-101, PROJ-133]
  status: active            # active | enforced | retired
  enforced_by: ""           # checks.yml id when enforced
  retired_reason: ""        # when retired, explain why (e.g., "merged into L-XXX")
```

## Check schema (`checks.yml`)

```yaml
- id: L-014                       # same id as the lesson it enforces
  pattern: '\bOrder\.(find|where)\b'   # Ruby regex, matched per changed line
  paths: app/                     # path prefix, optional
  message: "Order is legacy: use OrderV2"
```

A check only sees single lines. If a lesson can't be expressed as a line regex, keep it as
a lesson, or propose a spec for the user to commit later.

## Cause table

| Cause | Meaning | Fix goes to |
|---|---|---|
| `missing_knowledge` | not knowable from code or docs | lesson |
| `explore_miss` | findable, not found | lesson now; exploration method in `references/rails.md` if repeated |
| `spec_gap` | the ticket didn't say | a note for the user's ticket template |
| `ignored_instruction` | it was written down and not followed | check (the text already failed) |
| `ambiguous_instruction` | followed, but unclear | reword the lesson or skill text |
| `no_verification` | nothing would catch it | check, or a spec in this ticket |
| `wrong_judgment` | had the info, chose badly | the gate 2 plan checklist in `SKILL.md`, or accept as noise |

## Retro

1. **Gather.** Read `run.jsonl`. Human events are primary. Lasting domain facts from gate 1
   count. Agent events matter when one kind repeats 3+ times.

2. **Write lessons.** One line each: specific, actionable, naming files/symbols. Pick a
   cause from the table; add a one-line `cause_note`. User confirms the cause.

3. **Group** against all lessons in `lessons.yml`.
   - Similar lessons → merge. Extract the common principle in minimum words.
   - Instruct what to do, not what to avoid.
   - Prefer one broad principle over two narrow rules.

4. **Graduate** (in preference order):
   - **Skill instruction**: "What guideline would have prevented this?" → edit Working
     Style, a stage, or the subagent brief. Retire the lesson.
   - **Check**: `ignored_instruction`, or seen 2+ times and works as line regex.
   - **references/rails.md**: repeated `explore_miss`.
   - **Keep as lesson**: repo-specific facts only.

5. **Propose once.** Skill diffs, checks, ledger changes. Apply only what's approved.
   Graduated lessons get `status: retired`, `retired_reason: "graduated to <location>"`.

## Prune

Graduate lessons into skill instructions. A lesson means the skill was incomplete — prune
fixes the skill and retires the lesson.

### The graduation question

For each active lesson: **"What instruction would have prevented this?"**

| Answer points to... | Action |
|---|---|
| Working Style, a stage, subagent brief | Add instruction, retire lesson |
| references/rails.md | Add method, retire lesson |
| A line-regex check | Create check, retire lesson |
| Nothing generalizable | Keep as lesson |

### Workflow

1. `L score` — if rolling average isn't falling over 10+ tickets, name the dominant cause
   before continuing.
2. Walk each active lesson through the graduation question. Group lessons pointing to the
   same missing instruction. Propose skill diffs.
3. Merge duplicates — same teaching, different words.
4. `L stale` — refs that no longer exist. Ask: delete or update?
5. Over 30 active after graduation? Flag candidates to merge or sharpen.
6. Propose once. Apply what's approved.

### What stays

- Repo-specific facts that can't generalize
- New lessons not yet seen twice
- Lessons user chose to keep as reminders

Retired lessons stay with `status: retired` and `retired_reason` — the audit trail.

### Trigger

Every 10–20 tickets, when active > 30, or when one cause appears 3+ times recently.

## Later: when you start committing
Active lessons become `CLAUDE.md` lines (per area folder), and checks become RuboCop
custom cops or committed hooks. Until then, the ledger is the only home.
