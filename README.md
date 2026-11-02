# /ticket: a Claude Code skill for Rails tickets that learns

Runs a well-defined ticket end to end in a Rails repo with three human gates, then
holds a retro that teaches the flow something from every correction you make.

```
ticket → explore (subagent) → GATE 1 assumptions & questions → GATE 2 plan
       → failing specs → implement → self-review → GATE 3 diff → retro
```

## Install

```sh
git clone git@github.com:OlegSavinov/ticket-skill.git ~/.claude/skills/ticket
```

The path matters: the hooks call `~/.claude/skills/ticket/scripts/`.

Optional, for symbol lookup instead of grep:

```sh
gem install ruby-lsp          # under the Ruby your project uses
# inside Claude Code:
/plugin install ruby-lsp@claude-plugins-official
```

Requires git, Ruby 2.3+ (standard library only), and RSpec. RuboCop is used only if the
project already has it (`bin/rubocop` or in `Gemfile.lock`).

## Use

| Command | What it does |
|---|---|
| `/ticket PROJ-123` or `/ticket <pasted text>` | Run the full flow |
| `/ticket retro` | Rerun the retro for the open ticket |
| `/ticket prune` | Retire stale lessons, merge duplicates, report the score trend |
| `/ticket bug PROJ-123 <what broke>` | Log a post-merge bug and run a retro on it |

Use one Claude Code session per ticket. Once the skill runs, its hooks stay on for the
rest of the session, and they do nothing unless a ticket is open.

## Hooks

- **After every edit:** promoted checks (regex rules from past lessons) and RuboCop,
  reporting **only lines changed in this ticket**. Legacy offenses are left alone.
- **On stop:** the specs mapped from changed files
  (`app/models/x.rb` → `spec/models/x_spec.rb`, controllers → controller and request specs,
  `lib/` → `spec/lib/`). Failing specs block the stop up to 3 times in a row, then hand back
  to you. The run is skipped when nothing changed since the last green run.

## How it learns

Every correction is logged with a cause from a fixed list, and the cause decides where the
fix goes:

| Cause | Fix goes to |
|---|---|
| `missing_knowledge` | a lesson |
| `explore_miss` | a lesson, then the exploration method if it repeats |
| `spec_gap` | your ticket template |
| `ignored_instruction` | a promoted check (the text already failed) |
| `ambiguous_instruction` | reworded lesson or skill text |
| `no_verification` | a check or a spec |
| `wrong_judgment` | the plan checklist |

- The same lesson seen on 2+ tickets becomes a check the hook enforces.
- The same cause behind 3+ lessons triggers a change to that stage of the flow.
- You approve every change. Nothing edits itself unchecked.

**Score per ticket = 0.1 × agent-caught + 1.0 × human-caught**, with a rolling average over
the last 10 tickets. Lower is better. Moving catches from you to the hooks is the main way
the flow improves.

## Per-repo state

Each repo's state lives in `.claude/ticket/`, which `.git/info/exclude` excludes from git
locally, so it never gets committed:
`lessons.yml`, `checks.yml`, `log.yml`, `run.jsonl`, `state.json`.
If you start a ticket with uncommitted changes, they're snapshotted (`git stash create`,
nothing is touched), so your own work never counts as the agent's.

## Files

```
SKILL.md               the flow, gates, working style, hooks (frontmatter)
references/rails.md    lookup order: LSP → Rails introspection → grep; old-app traps
references/ledger.md   schemas, cause table, retro and prune procedures
scripts/hooklib.rb     pure logic shared by hooks and ledger
scripts/edit_hook.rb   PostToolUse hook
scripts/specs_hook.rb  Stop hook
scripts/ledger.rb      state CLI: init start event close bug score show stale
scripts/self_test.rb   ruby scripts/self_test.rb
```

## Credits

The working style in `SKILL.md` is adapted from
[Ponytail](https://github.com/DietrichGebert/ponytail) by DietrichGebert, MIT licensed.
Its notice is in `LICENSE-ponytail`.

## License

MIT, see `LICENSE`.
