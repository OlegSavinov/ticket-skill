---
inclusion: auto
name: ticket-retro
description: >
  Run the ticket retro stage only. Reviews the current ticket's run.jsonl, proposes
  ledger entries, check promotions, and skill edits based on what was learned.
  Use after completing a ticket or when explicitly requested.
---

# Ticket Retro

Run stage 8 (Retro) of the ticket workflow only.

`L` below means `ruby $HOME/.kiro/skills/ticket/scripts/ledger.rb`, run from the repo root.

## Retro

Read `$HOME/.kiro/skills/ticket/references/ledger.md` and follow its Retro section. Present one
proposal covering ledger entries, promotions and skill edits. Apply only what the user
approves, then `L close` and show the score lines. Commit nothing.

## Context

This shares state with the main ticket skill:
- State lives in `.claude/ticket/` (git-excluded locally)
- Uses the same ledger.rb script and ledger.md reference
- Operates on the currently open ticket's run.jsonl
