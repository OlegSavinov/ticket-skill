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
  retired_reason: ""
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

1. **Gather.** Read `.claude/ticket/run.jsonl`. Human events are the main input. Lasting
   domain facts from the gate 1 answers count too. Agent events matter when one kind
   repeats (the same cop 3+ times means a style lesson).
2. **Write each lesson** in one line: specific and actionable, naming the real files and
   symbols. Pick a cause and add a one-line `cause_note`. The user confirms the cause:
   your own diagnosis can be a plausible story rather than the truth.
3. **Dedupe** against `lessons.yml`, all statuses. Same lesson: add the ticket to `seen`,
   don't add a new entry. A retired lesson coming back: reactivate it and say it was
   retired too early.
4. **Promote**:
   - `ignored_instruction`: propose a check now.
   - `seen` has 2+ tickets and the lesson works as a line regex: propose a check.
   - The same cause on 3+ different active lessons: propose a change to that stage of
     `SKILL.md` or `references/rails.md` (`spec_gap`: to the user's ticket template),
     and retire the lessons it covers.
   - Not checkable: keep it as a lesson. If seen 2+ times, make the wording firmer.
   - Repo-specific facts go in the ledger. Process fixes that apply to any repo go in
     the skill files.
5. **Propose once**: one message with the YAML for new and changed entries, each check,
   skill edits as diffs, and template notes. Change nothing until the user approves.
6. **Apply** what's approved. A promoted lesson gets `status: enforced`, `fix: check` and
   `enforced_by: <id>`. Test each new check: it must flag the bad line from this ticket and
   not flag the fixed code.

## Prune

1. `L stale` lists lessons whose refs no longer exist. Propose retiring them, or updating
   the refs if the code moved (ask which).
2. Enforced lessons: confirm their check still exists in `checks.yml`.
3. Duplicates or conflicts: merge them, or ask which one wins.
4. More than 40 active lessons: merge or retire until under 40.
5. Not seen in the last 20 tickets: flag for the user to review, but never retire on age
   alone. No repeat corrections can mean the lesson works.
6. `L score`: report the trend. If the rolling average isn't falling over 10–20 tickets,
   say the loop isn't working and name the cause behind most human events.
7. Propose one diff and apply what's approved. Retired lessons stay in the file with
   `status: retired` and a `retired_reason`.

## Later: when you start committing
Active lessons become `CLAUDE.md` lines (per area folder), and checks become RuboCop
custom cops or committed hooks. Until then, the ledger is the only home.
