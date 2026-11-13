# Finding code in a Rails repo

Use this order and stop as soon as you have the answer.

## 1. LSP tool (if available)
Symbol search, definitions, references and file outlines, instead of reading files.

Static analysis misses code Rails generates at runtime, which is what step 2 covers.

## 2. Rails runtime introspection
This is the source of truth for generated code. Run from the repo root. Each call boots
the app, so batch several questions into one `runner` call. If boot fails (no DB,
missing env), say so and move on to step 3.

```sh
bin/rails routes -g orders                        # URL -> controller#action
grep -n 'create_table "orders"' -A 40 db/schema.rb   # one table, not the whole schema
bin/rails runner '
  m = Order
  puts m.ancestors.take_while { |a| a != ActiveRecord::Base }.inspect   # concerns, STI parents
  m.reflect_on_all_associations.each { |a| puts "#{a.macro} #{a.name} -> #{a.class_name}" }
  %w[validate save create update destroy commit].each do |k|
    m.send("_#{k}_callbacks").each { |c| puts "#{k}: #{c.kind} #{c.filter}" }
  end
  p m.instance_method(:cancel!).source_location    # where a method really lives
  p m.method(:active).source_location              # scopes / class methods
'
```

- `Object.const_source_location("OrderV2")` finds where a constant is defined (Ruby 2.7+).
- Old apps: `bundle exec rake routes`, `script/rails runner`, `ruby script/runner`, and
  `db/structure.sql` instead of `schema.rb`.

## 3. grep / git grep
Beyond `app/`, look in `lib/`, `app/*/concerns/`, engines (`engines/`, `components/`) and gems the
Gemfile loads with `path:`.

## Traps in old apps
- Two models for one concept (`Order`/`OrderV2`, `Legacy*`). Check which one is live.
- STI (`type` column), `default_scope`, callbacks that do the real work.
- `method_missing`, `define_method`, `delegate`, `alias_method_chain`.
- Monkey patches in `config/initializers/` and `lib/core_ext/`. Observers (Rails < 4).
