---
inclusion: auto
name: ticket-prune
description: >
  Graduate lessons into skill instructions. Reviews active lessons and asks what
  instruction would have prevented each one. Run every 10-20 tickets, when active
  lessons exceed 30, or when one cause repeats 3+ times.
---

# Ticket Prune

Graduate lessons into skill instructions.

`L` below means `ruby $HOME/.kiro/skills/ticket/scripts/ledger.rb`, run from the repo root.

## Prune

For each active lesson ask: **"What instruction would have prevented this?"** If it points
to Working Style, a stage, the subagent brief, or `references/rails.md` — add the
instruction and retire the lesson.

Read `$HOME/.kiro/skills/ticket/references/ledger.md` for the workflow.

## When to run

- Every 10–20 tickets
- When active lessons exceed 30
- When one cause repeats 3+ times

## Context

This shares state with the main ticket skill:
- State lives in `.claude/ticket/` (git-excluded locally)
- Uses the same ledger.rb script and ledger.md reference
- Operates on the repo's lesson ledger
