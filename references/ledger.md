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
  area: app/models          # path prefix it applies to; omit for repo-wide
  refs: [app/models/order_v2.rb, "OrderV2#cancel!"]   # paths or Const / Const#method
  seen: [PROJ-101, PROJ-133]
  status: active            # active | retired
  retired_reason: ""        # when retired, explain why (e.g., "merged into L-XXX")
```

## Check schema (`checks.yml`)

```yaml
- id: L-014                       # same id as the lesson it enforces
  pattern: '\bOrder\.(find|where)\b'   # Ruby regex, matched per changed line
  paths: app/                     # path prefix, optional
  message: "Order is legacy: use OrderV2"
```

A check with no `pattern` is a path rule: any edit under `paths` is flagged, or with
`only: create` only new files. Rules shipped with the skill live in
`references/repo-rules/<repo>.yml`.

A pattern check only sees single lines. If a lesson can't be expressed as a line regex, keep it as
a lesson, or propose a spec for the user to commit later.

## Cause table

| Cause | Meaning |
|---|---|
| `missing_knowledge` | not knowable from code or docs |
| `explore_miss` | findable, not found |
| `spec_gap` | the ticket didn't say |
| `ignored_instruction` | it was written down and not followed |
| `ambiguous_instruction` | followed, but unclear |
| `no_verification` | nothing would catch it |
| `wrong_judgment` | had the info, chose badly |

## Retro

1. **Gather.** Read `run.jsonl`. Human events come from a keyword match: delete lines
   that were answers to your questions, and add corrections it missed with
   `L event human <gate> "<what>"`. Human events are primary. Lasting domain facts from gate 1
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
   - **Check**: `ignored_instruction` (the text already failed), `no_verification` (or a
     spec in this ticket), or seen 2+ times and works as line regex.
   - **references/rails.md**: repeated `explore_miss`.
   - **Ticket template note**: `spec_gap`.
   - **Keep as lesson**: repo-specific facts only.

5. **Propose once.** Skill diffs, checks, ledger changes. Apply only what's approved.
   Graduated lessons get `status: retired`, `retired_reason: "graduated to <location>"`.

## Prune

A lesson means the skill was incomplete: prune fixes the skill and retires the lesson.

1. `L score` — if rolling average isn't falling over 10+ tickets, name the dominant cause
   before continuing.
2. Walk each active lesson through Retro step 4 (Graduate). Group lessons pointing to the
   same missing instruction. Propose skill diffs.
3. Merge duplicates — same teaching, different words.
4. `L stale` — refs that no longer exist. Ask: delete or update?
5. Over 30 active after graduation? Flag candidates to merge or sharpen.
6. Skill files: for each instruction graduated since the last prune, check it has one
   home and still changes behaviour. Delete duplicates and no-ops.
7. Propose once. Apply what's approved.

Lessons not yet seen twice, and lessons the user chose to keep as reminders, stay.
Retired lessons stay with `status: retired` and `retired_reason` — the audit trail.

Trigger: every 10–20 tickets, when active > 30, or when one cause appears 3+ times recently.
