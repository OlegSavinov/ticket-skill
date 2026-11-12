# /ticket state CLI. Run from the repo root.
#   init                      create .claude/ticket/, exclude it from git locally
#   start KEY [--force]       begin a ticket (activates hooks)
#   gate NAME                 set current gate (assumptions, plan, diff)
#   event agent|human SOURCE TEXT   log a caught error
#   close                     write metrics to log.yml, deactivate hooks
#   bug KEY TEXT              add a post-merge bug (human-caught) to KEY
#   score                     last 10 tickets + rolling average
#   show [PATH...]            active lessons, filtered by area prefix
#   stale                     lessons whose refs no longer exist
require_relative "hooklib"
require "fileutils"
H = TicketHooks

ROOT = H.git(Dir.pwd, "rev-parse", "--show-toplevel").strip
abort "ledger: not inside a git repo" if ROOT.empty?
DIR = H.state_dir(ROOT)
STATE = File.join(DIR, "state.json")
RUN = File.join(DIR, "run.jsonl")
LOG = File.join(DIR, "log.yml")
LESSONS = File.join(DIR, "lessons.yml")

def events
  File.exist?(RUN) ? File.readlines(RUN).map { |l| JSON.parse(l) } : []
end

def print_scores(log)
  log.last(10).each { |e| puts format("%-14s agent %2d  human %2d  score %5.1f", e["ticket"], e["agent"], e["human"], e["score"]) }
  puts "rolling avg (last 10): #{H.rolling(log.map { |e| e['score'] }) || 'n/a'}"
end

cmd = ARGV.shift
case cmd
when "init"
  FileUtils.mkdir_p(DIR)
  exclude = File.expand_path(H.git(ROOT, "rev-parse", "--git-path", "info/exclude").strip, ROOT)
  FileUtils.mkdir_p(File.dirname(exclude))
  current = File.exist?(exclude) ? File.read(exclude) : ""
  File.open(exclude, "a") { |f| f.puts("/.claude/ticket/") } unless current.include?("/.claude/ticket/")
  H.write_yaml(LESSONS, []) unless File.exist?(LESSONS)
  H.write_yaml(LOG, []) unless File.exist?(LOG)
  puts "ready: #{DIR} (git-excluded via #{exclude})"
when "start"
  key = ARGV.shift or abort "usage: start KEY"
  old = H.read_json(STATE, nil)
  if old && !events.empty? && !ARGV.include?("--force")
    abort "ticket #{old['ticket']} still open with #{events.size} events: run `close` first, or `start #{key} --force`"
  end
  # Dirty tree: snapshot it (no files, index or stash list touched) so the user's own
  # uncommitted work is not treated as the agent's change.
  snapshot = H.git(ROOT, "stash", "create").strip
  base = snapshot.empty? ? H.git(ROOT, "rev-parse", "HEAD").strip : snapshot
  untracked = H.git(ROOT, "ls-files", "--others", "--exclude-standard").split("\n")
  H.write_json(STATE, "ticket" => key, "base" => base, "untracked_at_start" => untracked,
                      "started" => Time.now.utc.iso8601, "blocks" => 0)
  File.write(RUN, "")
  puts "started #{key}, base #{base[0, 12]}#{snapshot.empty? ? '' : ' (snapshot of your uncommitted work)'}"
when "event"
  kind, source, text = ARGV
  abort "usage: event agent|human SOURCE TEXT" unless %w[agent human].include?(kind) && source && text
  abort "no active ticket" unless File.exist?(STATE)
  H.log_event(ROOT, kind, source, text)
  puts "logged #{kind}/#{source}"
when "gate"
  name = ARGV.shift or abort "usage: gate NAME (e.g., assumptions, plan, diff)"
  state = H.read_json(STATE, nil) or abort "no active ticket"
  state["current_gate"] = name
  H.write_json(STATE, state)
  puts "gate: #{name}"
when "close"
  state = H.read_json(STATE, nil) or abort "no active ticket"
  ev = events
  entry = { "ticket" => state["ticket"], "closed" => Time.now.utc.iso8601 }.merge(H.summarize(ev))
  entry["human_events"] = ev.select { |e| e["kind"] == "human" }.map { |e| "#{e['source']}: #{e['text']}" }
  entry["agent_by_source"] = ev.select { |e| e["kind"] == "agent" }.group_by { |e| e["source"] }
                               .map { |k, v| [k, v.size] }.to_h
  log = H.read_yaml(LOG, []) << entry
  H.write_yaml(LOG, log)
  File.delete(STATE)
  File.delete(RUN) if File.exist?(RUN)
  puts "closed #{entry['ticket']}: agent #{entry['agent']}, human #{entry['human']}, score #{entry['score']}"
  print_scores(log)
when "bug"
  key = ARGV.shift
  text = ARGV.join(" ")
  abort "usage: bug KEY TEXT" if key.nil? || text.empty?
  log = H.read_yaml(LOG, [])
  entry = log.reverse.find { |e| e["ticket"] == key } or abort "no closed ticket #{key} in log"
  entry["human"] += 1
  entry["score"] = H.score(entry["agent"], entry["human"])
  (entry["post_merge"] ||= []) << text
  H.write_yaml(LOG, log)
  puts "#{key}: human #{entry['human']}, score #{entry['score']}"
when "score"
  print_scores(H.read_yaml(LOG, []))
when "show"
  lessons = H.read_yaml(LESSONS, []).select { |l| l["status"] == "active" }
  unless ARGV.empty?
    lessons = lessons.select { |l| l["area"].nil? || ARGV.any? { |p| p.start_with?(l["area"]) || l["area"].start_with?(p) } }
  end
  lessons.each { |l| puts "#{l['id']} [#{l['cause']}] #{l['lesson']}#{l['area'] ? " (#{l['area']})" : ''}" }
  puts "(no active lessons)" if lessons.empty?
when "stale"
  path_exists = ->(p) { File.exist?(File.join(ROOT, p)) }
  grep = ->(pattern, *flags) { system("git", "-C", ROOT, "grep", "-q", *flags, "-E", pattern, out: File::NULL, err: File::NULL) }
  symbol_found = lambda do |const, meth|
    name = Regexp.escape(const.split("::").last)
    # lenient on methods: Rails generates many (associations, attributes), so any word hit counts
    grep.call("(class|module)[[:space:]]+([A-Za-z0-9_]+::)*#{name}([^A-Za-z0-9_]|$)") &&
      (meth.nil? || grep.call(Regexp.escape(meth.sub(/[!?=]\z/, "")), "-w"))
  end
  stale = H.read_yaml(LESSONS, []).reject { |l| l["status"] == "retired" }.map do |l|
    missing = H.stale_refs(l["refs"] || [], path_exists, symbol_found)
    [l["id"], missing] unless missing.empty?
  end.compact
  stale.each { |id, missing| puts "#{id}: missing #{missing.join(', ')}" }
  puts "(no stale refs)" if stale.empty?
else
  abort File.read(__FILE__).lines.take_while { |l| l.start_with?("#") }.join
end
