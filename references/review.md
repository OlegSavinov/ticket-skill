---
inclusion: manual
name: ticket-review
description: >
  Comprehensive code review using parallel subagents. Fetches ticket
  and diff, spawns four reviewers, synthesizes findings, then fixes or comments.
---

# Review

## Arguments

- `review` or `review self` — self-review, fix issues found
- `review pr <number>` — review external PR, post comments
- `review branch [<branch>]` — review local branch diff against main

## Stages

### 1. Fetch context
- **Jira ticket**: fetch with comments and linked issues (or use cached from current session)
- **Diff**: 
  - Self/branch: `git diff <base>` (base from `.claude/ticket/state.json` or main)
  - External PR: `gh pr diff <number>`
- **PR metadata** (if PR): `gh pr view <number> --json number,title,body,author`

State in ≤5 lines: ticket goal, what the diff changes.

### 2. Spawn reviewers (parallel)
Launch four subagents with this shared context:
```
Ticket: <jira text, ≤20 lines>
Diff: <full diff>
Repo rules: <from repo-rules/ if exists>
```

**2.1 Ponytail review** (load `ponytail-review` skill):
```
Run ponytail-review on this diff. Return findings as a numbered list.
```

**2.2 Code review** (load `code-review` skill):
```
Run code-review skill on this diff. Return findings as a numbered list with file:line references.
```

**2.3 Constraint review** (general subagent):
```
Review this diff against these criteria:

1. Hard constraints: check repo rules violations
2. Ticket completeness: compare each acceptance criterion from the Jira ticket against
   the implementation. Flag any criterion that isn't covered or is implemented
   differently than specified. Each criterion needs a spec.
3. Validation/business logic: for any validation or business logic changes, state the
   rule in plain English, then trace every branch in the code to confirm it matches.
   "When X and Y are configured, the code does Z" — verify Z is correct per the ticket.
4. Comment hygiene: flag comments that restate the code (e.g.
   "# User is explicitly setting status"). Comments are for *why*, not *what*.
5. Execution cleanness: no debug code, commented code, or temp fixes
6. Logic sense: does the approach make sense for the problem?

Return findings as a numbered list, grouped by category.
```

**2.4 Waste management** (general subagent):
```
Read <skill dir>/references/waste_management.md and review this diff by it.
```

### 3. Synthesize
Collect all findings. Classify:
- **Must fix**: bugs, security, data loss risks, broken functionality
- **Should fix**: performance issues, missing edge cases, guideline violations
- **Nit**: style, minor simplifications, nice-to-haves

Deduplicate overlapping findings. Present as one prioritized list (≤15 items).

### 4. Act

**4.1 Self-review** (`review` or `review self` or `review branch`):
- Fix each must-fix and should-fix item
- Log fixes: `L event agent review "<what>"`
- For contested items, use the **Spec-first bug procedure**: if you can't write a failing
  spec for the claimed bug, note it as "could not reproduce"
- After fixes, re-run affected specs

**4.2 External PR** (`review pr <number>`):
- Post findings as PR review comments
- Prefix each comment with `🤖` 
- Group related findings into single comments where sensible
- Use GitHub review API:
  ```bash
  # Submit review with comments
  gh api repos/{owner}/{repo}/pulls/{pr}/reviews -f event=COMMENT -f body="🤖 Review summary..." \
    --field comments='[{"path":"file.rb","line":10,"body":"🤖 Finding..."}]'
  ```
- For must-fix items, request changes; otherwise comment only

### 5. Report
End with:
- Findings addressed (count)
- Findings skipped with reason
- Any items needing user decision
