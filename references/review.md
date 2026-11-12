---
inclusion: manual
name: ticket-review
description: >
  Comprehensive code review using parallel subagents. Compacts context, fetches ticket
  and diff, spawns three reviewers, synthesizes findings, then fixes or comments.
---

# Review

Comprehensive review using parallel subagents.

## Arguments

- `review` or `review self` — self-review, fix issues found
- `review pr <number>` — review external PR, post comments
- `review branch [<branch>]` — review local branch diff against main

## Working style

Same as ticket skill: terse, no fluff. Focus on what matters.

## Stages

### 1. Compact
Request context compaction with instruction: "Preparing for code review. Preserve:
ticket key, branch name, base commit."

### 2. Fetch context
- **Jira ticket**: fetch with comments and linked issues (or use cached from current session)
- **Diff**: 
  - Self/branch: `git diff <base>` (base from `.claude/ticket/state.json` or main)
  - External PR: `gh pr diff <number>`
- **PR metadata** (if PR): `gh pr view <number> --json number,title,body,author`

State in ≤5 lines: ticket goal, what the diff changes.

### 3. Spawn reviewers (parallel)
Launch three subagents with this shared context:
```
Ticket: <jira text, ≤20 lines>
Diff: <full diff>
Repo rules: <from repo-rules/ if exists>
```

**3.1 Ponytail review** (load `ponytail-review` skill):
```
Run ponytail-review on this diff. Return findings as a numbered list.
Focus: logic correctness, safety, load handling, test coverage, unnecessary code.
```

**3.2 Code review** (load `code-review` skill):
```
Run code-review skill on this diff. Return findings as a numbered list with file:line references.
```

**3.3 Constraint review** (general-task-execution):
```
Review this diff against these criteria:

1. Hard constraints: check repo rules violations
2. Ticket completeness: compare each acceptance criterion from the Jira ticket against
   the implementation. Flag any criterion that isn't covered or is implemented
   differently than specified.
3. Validation/business logic: for any validation or business logic changes, state the
   rule in plain English, then trace every branch in the code to confirm it matches.
   "When X and Y are configured, the code does Z" — verify Z is correct per the ticket.
4. Comment hygiene: no explanatory comments on obvious code. Comments like
   "# User is explicitly setting status" restate what the code says. Delete them.
   Comments are for *why*, not *what*.
5. Execution cleanness: no debug code, commented code, or temp fixes
6. Ticket skill guidelines: smallest complete change, reuses existing code, specs for
   each criterion
7. Logic sense: does the approach make sense for the problem?
8. Overcomplications: unnecessary abstractions, premature optimization, YAGNI violations

Return findings as a numbered list, grouped by category.
```

### 4. Synthesize
Collect all findings. Select the most important using judgment:
- **Must fix**: bugs, security, data loss risks, broken functionality
- **Should fix**: performance issues, missing edge cases, guideline violations
- **Nit**: style, minor simplifications, nice-to-haves

Deduplicate overlapping findings. Present as one prioritized list (≤15 items).

### 5. Act

**5.1 Self-review** (`review` or `review self` or `review branch`):
- Fix each must-fix and should-fix item
- Log fixes: `L event agent review "<what>"`
- For contested items, use the **Spec-first bug procedure**: if you can't write a failing
  spec for the claimed bug, note it as "could not reproduce"
- After fixes, re-run affected specs

**5.2 External PR** (`review pr <number>`):
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

### 6. Report
End with:
- Findings addressed (count)
- Findings skipped with reason
- Any items needing user decision
