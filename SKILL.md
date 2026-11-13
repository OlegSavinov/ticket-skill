---
name: ticket
description: >
  Run a ticket end to end in a Rails repo with three human gates and a learning loop:
  explore, assumptions and questions, plan, failing specs first, implement, self-review,
  diff review, then a retro that teaches the flow through a per-repo lesson ledger.
  Subcommands: bug, defend, review, retro, prune.
disable-model-invocation: true
argument-hint: "<JIRA-KEY | pasted ticket> | bug <KEY> <what broke> | defend [<KEY>] | review [self|pr <N>|branch] | retro | prune"
allowed-tools: Bash(ruby ${CLAUDE_SKILL_DIR}/scripts/*), Write, Edit, MultiEdit
hooks:
  PostToolUse:
    - matcher: "Edit|Write|MultiEdit"
      hooks:
        - type: command
          command: 'ruby "$HOME/.claude/skills/ticket/scripts/edit_hook.rb"'
          timeout: 120
  Stop:
    - hooks:
        - type: command
          command: 'ruby "$HOME/.claude/skills/ticket/scripts/specs_hook.rb"'
          timeout: 900
  UserPromptSubmit:
    - hooks:
        - type: command
          command: 'ruby "$HOME/.claude/skills/ticket/scripts/feedback_hook.rb"'
          timeout: 10
---

# /ticket

Arguments: `$ARGUMENTS`

- `bug <KEY> <text>` → Bug.
- `defend [<KEY>]` → Defend PR (load `references/defend.md`).
- `review [self|pr <number>|branch [<name>]]` → Review (load `references/review.md`).
- `retro` → stage 8 only. `prune` → the Prune section of `references/ledger.md`.
- Anything else is a ticket (Jira key or pasted text): run stages 0–8 in order.
- A non-code ticket (research, decision): also load `references/non-code.md`.

`L` below means `ruby ${CLAUDE_SKILL_DIR}/scripts/ledger.rb`, run from the repo root.
State lives in `.claude/ticket/` (git-excluded locally). One session per ticket: the hooks
stay on for the rest of the session once this skill runs, and do nothing without an
active ticket.

## Working style

Applies to every stage and goes, condensed, into every subagent brief.

- Lazy about the method, never about the result: least effort, fewest words, least new
  code, never at the cost of correctness.
- Work priority: delete -> extend -> create. Never at a cost of code quality and readabilty.
- Lead with the result. Short sentences, everyday words. A list or table only when it is
  shorter than prose. One recommendation, not a survey.
- Ask only what is truly the user's call. Answer the rest from the code or a sensible
  default, and name the default.
- Scope is the ticket. No cleanups, reformatting, "while I'm here" edits or legacy
  RuboCop fixes. Name a useful extra in one line instead of doing it.
- Smallest complete change: reuse what the codebase has (helpers, concerns, service
  patterns), then Ruby/Rails, then installed gems. Never add a gem for a few lines.
- Services take models, return models: prefer high-level domain objects (ActiveRecord
  models, value objects) over primitives or hashes as inputs and outputs. A service that
  takes `(user, loan)` is easier to follow than one that takes `(user_id, loan_id, status,
  amount)`. The signature should read like the business operation it performs.
- Finish everything the change needs: grep every caller of what you touch, update specs,
  factories and fixtures. Fix root causes once, in the shared code.
- Comment only the why the code can't show. A shortcut with a known limit gets
  `# shortcut: <the limit>, <when to upgrade>`.
- Never cut validation at trust boundaries, error handling that prevents data loss,
  security, or anything the ticket asks for.
- Commit, push or open a PR only when the user asks. Never rewrite git history.
- Always run `git commit` as a standalone command, never chained with other tool calls in the same response. Only commit once the code is verified safe and all edits are complete — hooks must run cleanly on the final state, not on a partially-modified file.
- Never launch a command that touches the DB while a previous one is still running — wait for completion first.
- Stuck after two tries: stop and say what failed.
- End every gate message with one line: what you skipped or didn't check, and any risk.

## Logging caught errors

The hooks log their own catches: the edit and specs hooks as `agent`, the feedback hook
as `human` (user messages that match correction keywords).
Log by hand only `L event agent review "<what>"`: each issue self-review (stage 7)
catches and fixes.

Score per ticket = 0.1 × agent-caught + 1.0 × human-caught + 2.0 × review-caught. Lower is better.
- **agent-caught**: hooks or self-review found it
- **human-caught**: user caught it during gates
- **review-caught**: code review comments from other developers (GitHub PR reviews)

Moving catches earlier (review → human → agent) is how the flow improves.

## Stages

### 0. Setup
- `L init`, then `L start <KEY>` (pasted text without a key: use a short slug). If a
  previous ticket is still open, ask before `--force`. `start` prints the base commit
  (also kept in `.claude/ticket/state.json`). On a dirty tree it is a snapshot of the
  user's uncommitted work, so that work never counts as part of this ticket.
- **Load repo rules**: check `${CLAUDE_SKILL_DIR}/references/repo-rules/` for a file
  matching the repo name. If found, load it — these are hard rules that block the workflow.
- If the `LSP` tool is unavailable, say once: "No LSP: run
  `/plugin install ruby-lsp@claude-plugins-official` for symbol lookup. Using
  introspection and grep." Continue.
- If feature branch does not exist yet - create it via `git checkout -b AI-{{ticket_id}}-{{short_description}}`

### 1. Ticket
- Jira key and a Jira tool available: fetch it, with its comments and linked issues.
  Otherwise ask the user to paste it.
- Extract in at most 15 lines: outcome, acceptance criteria, constraints, non-goals.
  Sources: the ticket, its comments, and anything the user said earlier in this
  conversation. Decisions often live outside the description.
- Every requirement the user stated goes into the criteria. Never move one into
  non-goals or "later" yourself; if it looks out of scope, ask at gate 1.
- Anything missing or vague becomes a gate 1 question.

### 2. Explore (subagent)
Run `L show` for the repo's active lessons. Spawn one Explore subagent with this brief:

```
Find the code for this ticket in a Rails repo. Do not edit anything.
Ticket: <extracted ticket>
Known lessons for this repo (trust these over what the code seems to say): <L show output>
Method: read ${CLAUDE_SKILL_DIR}/references/rails.md and follow its lookup order.
Read only what answers the questions below.
Style: lazy about the method, never about the result. Terse.
Return at most 60 lines:
- entry points and the code path, as path:line
- models, associations, callbacks, concerns involved (from introspection, not guesses)
- existing specs and factories for this area
- traps: duplicate or legacy variants (V2, Legacy*, old namespaces), dead code,
  metaprogramming, monkey patches
- what you could not determine
```

Read files yourself only where the summary leaves a gap the plan depends on.

### 3. Gate 1: assumptions and questions (STOP)
Run `L gate assumptions` to mark the current gate.
- **Why**: one sentence — the problem being solved or outcome being enabled.
- **Assumptions**, numbered: "I'll assume X, because <path:line or the default>."
- **Questions**: only choices that are truly the user's, each with your recommendation.
- **Unsettled edge cases**: each with what you'd do by default.
- Skipped/risk line.

Wait for the answer. Keep answers that are lasting domain facts for the retro.

### 4. Gate 2: plan (STOP)
Run `L gate plan` to mark the current gate. Enter plan mode. First describe the intended flow:
- For user-facing features: "Open X → See Y → Do Z → `BackendService.call` → Result"
- For backend tasks: show the execution path (e.g., "`LoanStep.submit` callback → `BackgroundJob.perform_later` → `Processor.review` → POST API call")
Keep it concrete with actual class/method names.

The plan:
- Approach in 2–5 lines, reusing what exists.
- Files to change, each with why, plus affected callers.
- Specs to add or change, each mapped to an acceptance criterion.
- Risks, and what is out of scope.

Wait for approval.

### 5. Failing specs first
Write specs for each criterion. Extend existing spec files and factories in their style.
Run them (`bundle exec rspec <files>`). Each must fail for the right reason, missing
behavior, not a load, factory or syntax error. Fix the setup until that's true.

### 6. Implement
Make the smallest complete change that turns the specs green. Fix what the hooks report.
Never disable a cop, skip a spec or edit a check to get past them.
Also run the spec files for affected callers the plan named.

### 7. Self-review, then gate 3: diff (STOP)
- Run `review self` (load `references/review.md`) on the diff since base.
- Run `L gate review` to mark the current gate.
- Gate message: `git diff --stat <base>`, what changed in at most 10 lines, each criterion
  with its spec (all green), the review verdict, the skipped/risk line.

Wait. Apply fixes and return to this gate.

### 8. Retro
Read `${CLAUDE_SKILL_DIR}/references/ledger.md` and follow its Retro section. Present one
proposal covering ledger entries, promotions and skill edits. Apply only what the user
approves, then `L close` and show the score lines.

## Bug
`L bug <KEY> "<what broke>"`. Then run the Retro section with the bug as its only event
(ignore `run.jsonl`, which belongs to whatever ticket is open). The bug got past every
gate, so also ask which gate should have caught it.

When fixing any bug — whether from a bug report or discovered mid-ticket — follow the
**Spec-first bug procedure** below.

## Creating PRs

When the user asks for a PR, two steps preserve the repo's PR template:

1. **Create with template**: `gh pr create --title "KEY: description" --fill`
   - Never pass `--body` on create — it overwrites the template

2. **Fill in template**: `gh pr edit <number> --body '...'`
   - Fill in JIRA link, Summary bullets
   - Keep ALL checkboxes — check only what applies, never delete lines

## Spec-first bug procedure

Before fixing any reported bug or flaw:

1. **Build the mental model**: describe the scenario that breaks the flow. What inputs,
   what state, what sequence of calls leads to the failure? If you cannot articulate
   this, you do not understand the bug yet.
2. **Write the failing spec**: translate that scenario into a spec. It must fail for the
   exact reason described — same error, same line. If it passes or fails differently,
   your mental model is wrong; revise it.
3. **Fix the code**: only after the spec is red for the right reason.
4. **Verify**: spec turns green, no other specs break.

If you cannot produce a failing spec, say so. Either the scenario is not real, or you
lack the context to reproduce it — both are useful information.
