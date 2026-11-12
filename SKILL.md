---
name: ticket
description: >
  Run a ticket end to end in a Rails repo with three human gates and a learning loop:
  explore, assumptions and questions, plan, failing specs first, implement, self-review,
  diff review, then a retro that teaches the flow through a per-repo lesson ledger.
  Subcommands: bug. For retro/prune, load references/retro.md or references/prune.md.
disable-model-invocation: true
argument-hint: "<JIRA-KEY | pasted ticket> | bug <KEY> <what broke>"
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
- Anything else is a ticket (Jira key or pasted text): run stages 0–8 in order.

For standalone retro or prune, load the reference files `references/retro.md` or
`references/prune.md` on demand.

`L` below means `ruby ${CLAUDE_SKILL_DIR}/scripts/ledger.rb`, run from the repo root.
State lives in `.claude/ticket/` (git-excluded locally). One session per ticket: the hooks
stay on for the rest of the session once this skill runs, and do nothing without an
active ticket.

## Working style

Applies to every stage and goes, condensed, into every subagent brief.

- Lazy about the method, never about the result: least effort, fewest words, least new
  code, never at the cost of correctness.
- Always look for an opportunity to produce less: concise responses, keywords as a comment.
- Work priority: delete -> extend -> create. Never at a cost of code quality and readabilty.
- Lead with the result. Short sentences, everyday words. A list or table only when it is
  shorter than prose. One recommendation, not a survey.
- Ask only what is truly the user's call. Answer the rest from the code or a sensible
  default, and name the default.
- Scope is the ticket. No cleanups, reformatting, "while I'm here" edits or legacy
  RuboCop fixes. Name a useful extra in one line instead of doing it.
- Smallest complete change: reuse what the codebase has (helpers, concerns, service
  patterns), then Ruby/Rails, then installed gems. Never add a gem for a few lines.
- Finish everything the change needs: grep every caller of what you touch, update specs,
  factories and fixtures. Fix root causes once, in the shared code.
- Comment only the why the code can't show. A shortcut with a known limit gets
  `# shortcut: <the limit>, <when to upgrade>`.
- Never cut validation at trust boundaries, error handling that prevents data loss,
  security, or anything the ticket asks for.
- Never commit, push or rewrite git history. Confirm before anything destructive.
- Always run `git commit` as a standalone command, never chained with other tool calls in the same response. Only commit once the code is verified safe and all edits are complete — hooks must run cleanly on the final state, not on a partially-modified file.
- Stuck after two tries: stop and say what failed.
- End every gate message with one line: what you skipped or didn't check, and any risk.

## Logging caught errors

The hooks log catches automatically:
- **Edit hook**: promoted checks and RuboCop violations on changed lines → `agent`
- **Specs hook**: failing specs → `agent`
- **Feedback hook**: user corrections/instructions at gates → `human`

Manual logging (still needed):
- `L event agent review "<what>"`: issues your self-review (stage 7) catches and fixes.

The feedback hook detects corrections, questions, and substantive instructions. Simple
approvals ("ok", "lgtm", "proceed") are not logged.

Score per ticket = 0.1 × agent-caught + 1.0 × human-caught. Lower is better. An error a
hook catches costs a tenth of one the user catches, so moving catches from the user to
the hooks is the main way the flow improves.

## Stages

### 0. Setup
- `L init`, then `L start <KEY>` (pasted text without a key: use a short slug). If a
  previous ticket is still open, ask before `--force`. `start` prints the base commit
  (also kept in `.claude/ticket/state.json`). On a dirty tree it is a snapshot of the
  user's uncommitted work, so that work never counts as part of this ticket.
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
- Anything missing or vague becomes a gate 1 question. Don't pad.

### 2. Explore (subagent)
Run `L show` for the repo's active lessons. Spawn one Explore subagent with this brief:

```
Find the code for this ticket in a Rails repo. Do not edit anything.
Ticket: <extracted ticket>
Known lessons for this repo (trust these over what the code seems to say): <L show output>
Method: read ${CLAUDE_SKILL_DIR}/references/rails.md and follow its lookup order
(LSP tool, then Rails introspection, then grep). Prefer symbol lookups over reading
whole files. Read only what answers the questions below.
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

Wait for the answer. The feedback hook logs user corrections automatically. Keep answers
that are lasting domain facts for the retro.

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

Wait for approval. The feedback hook logs user corrections automatically.

### 5. Failing specs first
Write specs for each criterion. Extend existing spec files and factories in their style.
Run them (`bundle exec rspec <files>`). Each must fail for the right reason, missing
behavior, not a load, factory or syntax error. Fix the setup until that's true.

### 6. Implement
Make the smallest complete change that turns the specs green. The hooks enforce:
- after each edit: promoted checks and RuboCop, on the lines you changed only;
- on every stop: the specs mapped from changed files (blocks up to 3 times, then hands
  back to the user).

Fix what they report. Never disable a cop, skip a spec or edit a check to get past them.
Also run the spec files for affected callers the plan named.

### 7. Self-review, then gate 3: diff (STOP)
- Run the `ponytail-review` skill on the diff since base (`git diff <base>` plus new
  files). Fix every bug and risk it finds, logging each with `L event agent review "<what>"`.
  Apply simplifications only inside the ticket's scope.
- **Check every line in the diff:**
  - Does it bear on the ticket? Remove lines that don't.
  - Is it the minimum code to express the intent? Simplify what isn't.
- Run `L gate review` to mark the current gate.
- Gate message: `git diff --stat <base>`, what changed in at most 10 lines, each criterion
  with its spec (all green), the review verdict, the skipped/risk line.

Wait. The feedback hook logs user corrections automatically. Apply fixes and return to this gate.

### 8. Retro
Read `${CLAUDE_SKILL_DIR}/references/ledger.md` and follow its Retro section. Present one
proposal covering ledger entries, promotions and skill edits. Apply only what the user
approves, then `L close` and show the score lines. Commit nothing.

## Bug
`L bug <KEY> "<what broke>"`. Then run the Retro section with the bug as its only event
(ignore `run.jsonl`, which belongs to whatever ticket is open). The bug got past every
gate, so also ask which gate should have caught it.

When fixing any bug — whether from a bug report or discovered mid-ticket — write a spec
first that fails with the exact same error from the exact same line, then fix the code.
The spec must be red for the right reason before any implementation change is made.
