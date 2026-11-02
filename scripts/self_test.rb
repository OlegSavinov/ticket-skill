# Assert-based self-check for hooklib. Run: ruby self_test.rb (exit 1 on failure).
require_relative "hooklib"

FAILS = []
def check(name)
  ok = yield
  FAILS << name unless ok
  puts "#{ok ? 'ok  ' : 'FAIL'} #{name}"
rescue StandardError => e
  FAILS << name
  puts "FAIL #{name}: #{e.class}: #{e.message}"
end

H = TicketHooks

# --- spec mapping
check("model maps to model spec") { H.spec_candidates("app/models/order.rb") == ["spec/models/order_spec.rb"] }
check("nested service maps") { H.spec_candidates("app/services/billing/charge.rb") == ["spec/services/billing/charge_spec.rb"] }
check("controller maps to controller + request spec") do
  H.spec_candidates("app/controllers/admin/orders_controller.rb") ==
    ["spec/controllers/admin/orders_controller_spec.rb", "spec/requests/admin/orders_spec.rb"]
end
check("lib maps to spec/lib") { H.spec_candidates("lib/tax/calc.rb") == ["spec/lib/tax/calc_spec.rb"] }
check("spec file maps to itself") { H.spec_candidates("spec/models/order_spec.rb") == ["spec/models/order_spec.rb"] }
check("non-ruby and other paths map to nothing") do
  H.spec_candidates("app/views/orders/show.html.erb") == [] && H.spec_candidates("config/routes.rb") == []
end
check("relevant_specs keeps existing, unique, sorted") do
  exists = ->(p) { p != "spec/requests/orders_spec.rb" }
  H.relevant_specs(["app/models/order.rb", "spec/models/order_spec.rb", "app/controllers/orders_controller.rb", "README.md"], exists) ==
    ["spec/controllers/orders_controller_spec.rb", "spec/models/order_spec.rb"]
end

# --- changed lines from `git diff -U0`
DIFF = <<-D
diff --git a/app/models/order.rb b/app/models/order.rb
--- a/app/models/order.rb
+++ b/app/models/order.rb
@@ -3,0 +4,2 @@ class Order
+  a
+  b
@@ -10 +12 @@ def x
-  old
+  new
@@ -20,3 +21,0 @@ def y
D
check("changed_lines parses add, single-line and delete-only hunks") { H.changed_lines(DIFF).sort == [4, 5, 12] }
check("changed_lines of empty diff is empty") { H.changed_lines("").empty? }

# --- offense filtering
RC = {
  "files" => [{ "path" => "app/models/order.rb", "offenses" => [
    { "cop_name" => "Style/A", "message" => "new line", "location" => { "start_line" => 4 } },
    { "cop_name" => "Style/B", "message" => "legacy line", "location" => { "start_line" => 30 } }
  ] }]
}
check("filter_offenses keeps only changed lines") { H.filter_offenses(RC, [4, 5]).map { |o| o["cop_name"] } == ["Style/A"] }
check("filter_offenses with nil lines keeps all (untracked file)") { H.filter_offenses(RC, nil).size == 2 }
check("filter_offenses tolerates empty json") { H.filter_offenses({}, [1]) == [] }
check("filter_offenses reads old rubocop format (location.line only)") do
  old = { "files" => [{ "offenses" => [{ "cop_name" => "X", "message" => "m", "location" => { "line" => 4 } }] }] }
  H.filter_offenses(old, [4]).size == 1 && H.format_offenses("a.rb", H.filter_offenses(old, [4])).include?("a.rb:4")
end
check("format_offenses names file, line and cop") do
  s = H.format_offenses("app/models/order.rb", H.filter_offenses(RC, [4]))
  s.include?("app/models/order.rb:4") && s.include?("Style/A")
end

# --- promoted checks (checks.yml) on changed lines
CHECKS = [
  { "id" => "L-014", "pattern" => "\\bOrder\\.find\\b", "paths" => "app/", "message" => "use OrderV2" },
  { "id" => "L-020", "pattern" => "puts", "paths" => "lib/", "message" => "no puts in lib" }
]
SRC = ["class X", "  Order.find(1)", "  OrderV2.find(1)", "  Order.find(2)"]
check("check_violations flags only changed lines in matching paths") do
  v = H.check_violations(CHECKS, "app/models/x.rb", SRC, [2, 3])
  v.size == 1 && v.first.include?("app/models/x.rb:2") && v.first.include?("L-014")
end
check("check_violations with nil lines scans whole file") { H.check_violations(CHECKS, "app/models/x.rb", SRC, nil).size == 2 }
check("check_violations skips non-matching paths and bad regex") do
  H.check_violations(CHECKS, "spec/x_spec.rb", SRC, nil).empty? &&
    H.check_violations([{ "id" => "B", "pattern" => "(" }], "app/x.rb", SRC, nil).empty?
end

# --- scoring
check("score weights agent 0.1, human 1.0") { H.score(3, 2) == 2.3 }
check("summarize counts events by kind") do
  ev = [{ "kind" => "agent" }, { "kind" => "agent" }, { "kind" => "human" }, { "kind" => "other" }]
  H.summarize(ev) == { "agent" => 2, "human" => 1, "score" => 1.2 }
end
check("rolling averages the last n") { H.rolling([10, 1, 2, 3], 3) == 2.0 }
check("rolling of nothing is nil") { H.rolling([], 10).nil? }

# --- stop-hook loop limit
check("should_block? allows up to max attempts") { H.should_block?(1) && H.should_block?(3) && !H.should_block?(4) }

# --- ledger refs
check("ref_kind splits paths and symbols") do
  H.ref_kind("app/models/order_v2.rb") == :path && H.ref_kind("OrderV2#cancel!") == :symbol && H.ref_kind("OrderV2") == :symbol
end
check("parse_symbol splits constant and method") do
  H.parse_symbol("Billing::OrderV2#cancel!") == ["Billing::OrderV2", "cancel!"] &&
    H.parse_symbol("OrderV2.build") == ["OrderV2", "build"] && H.parse_symbol("OrderV2") == ["OrderV2", nil]
end
check("stale_refs returns missing refs only") do
  H.stale_refs(["a.rb", "Gone#x", "Here#y"], ->(p) { p == "a.rb" }, ->(c, m) { c == "Here" }) == ["Gone#x"]
end

puts FAILS.empty? ? "\nALL PASS" : "\n#{FAILS.size} FAILED"
exit(FAILS.empty? ? 0 : 1)
