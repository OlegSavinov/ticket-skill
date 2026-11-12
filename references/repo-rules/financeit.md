# FinanceIt repo rules

Hard rules for the financeit repo. Violations block the workflow — no exceptions.

## File restrictions

1. **Never write to `spec/fixtures/files/production.crontab`** — this file is generated,
   not hand-edited.

2. **Never create files directly in `db/`** — always use `rails generate migration` to
   create new migrations. The generator ensures proper timestamps and naming.

## Required actions

3. **After any change to `config/schedule.rb`** — run:
   ```bash
   RERECORD=1 rspec spec/whenever_spec.rb
   ```
   This re-records the crontab fixture. Commit the updated fixture with your change.
