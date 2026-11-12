# Pure logic shared by the /ticket hooks and ledger. Stdlib only, Ruby 2.3+ compatible
# (hooks run under the project's Ruby, which may be old).
require "json"
require "yaml"
require "open3"
require "time"

module TicketHooks
  MAX_STOP_BLOCKS = 3
  AGENT_WEIGHT = 0.1
  HUMAN_WEIGHT = 1.0
  REVIEW_WEIGHT = 2.0

  module_function

  # --- repo state -------------------------------------------------------------

  def root(input = {})
    ENV["CLAUDE_PROJECT_DIR"] || input["cwd"] || Dir.pwd
  end

  def state_dir(root)
    File.join(root, ".claude", "ticket")
  end

  def read_json(path, default)
    File.exist?(path) ? JSON.parse(File.read(path)) : default
  rescue JSON::ParserError
    default
  end

  def write_json(path, data)
    File.write(path, JSON.pretty_generate(data) + "\n")
  end

  def read_yaml(path, default)
    return default unless File.exist?(path)
    YAML.safe_load(File.read(path)) || default
  end

  def write_yaml(path, data)
    File.write(path, YAML.dump(data))
  end

  def log_event(root, kind, source, text)
    dir = state_dir(root)
    state = read_json(File.join(dir, "state.json"), {})
    ev = { "t" => Time.now.utc.iso8601, "ticket" => state["ticket"], "kind" => kind, "source" => source, "text" => text }
    File.open(File.join(dir, "run.jsonl"), "a") { |f| f.puts(JSON.generate(ev)) }
  end

  def git(root, *args)
    out, status = Open3.capture2("git", "-C", root, *args)
    status.success? ? out : ""
  end

  # --- spec mapping -----------------------------------------------------------

  def spec_candidates(path)
    return [path] if path =~ %r{\Aspec/.+_spec\.rb\z}
    if (m = path.match(%r{\Aapp/([^/]+)/(.+)\.rb\z}))
      type, rest = m[1], m[2]
      list = ["spec/#{type}/#{rest}_spec.rb"]
      list << "spec/requests/#{rest.sub(/_controller\z/, '')}_spec.rb" if type == "controllers" && rest.end_with?("_controller")
      return list
    end
    return ["spec/lib/#{$1}_spec.rb"] if path =~ %r{\Alib/(.+)\.rb\z}
    []
  end

  def relevant_specs(changed, exists = ->(p) { File.exist?(p) })
    changed.map { |p| spec_candidates(p) }.flatten.uniq.select { |p| exists.call(p) }.sort
  end

  # --- changed lines from `git diff -U0` -------------------------------------

  def changed_lines(diff)
    lines = []
    diff.each_line do |l|
      next unless (m = l.match(/\A@@ -\S+ \+(\d+)(?:,(\d+))? @@/))
      start = m[1].to_i
      count = m[2] ? m[2].to_i : 1
      count.times { |i| lines << start + i }
    end
    lines
  end

  # --- rubocop ----------------------------------------------------------------

  # lines == nil means "every line" (untracked, brand-new file).
  def filter_offenses(rubocop_json, lines)
    files = rubocop_json["files"] || []
    offenses = files.map { |f| f["offenses"] || [] }.flatten
    return offenses if lines.nil?
    offenses.select { |o| lines.include?(offense_line(o)) }
  end

  # Old RuboCop JSON has only location.line; newer adds start_line.
  def offense_line(o)
    o["location"]["start_line"] || o["location"]["line"]
  end

  def format_offenses(path, offenses)
    offenses.map { |o| "#{path}:#{offense_line(o)} #{o['cop_name']}: #{o['message']}" }.join("\n")
  end

  # --- promoted checks (.claude/ticket/checks.yml) ---------------------------

  # checks: [{id, pattern (Ruby regex), paths (prefix, optional), message}]
  # file_lines: file content as array; lines: changed line numbers, nil = all.
  def check_violations(checks, rel, file_lines, lines)
    out = []
    checks.each do |c|
      next if c["paths"] && !rel.start_with?(c["paths"])
      re = begin
        Regexp.new(c["pattern"].to_s)
      rescue RegexpError
        next # a broken check must not block edits
      end
      (lines || (1..file_lines.size).to_a).each do |n|
        text = file_lines[n - 1]
        out << "#{rel}:#{n} [#{c['id']}] #{c['message']}" if text && text =~ re
      end
    end
    out
  end

  # --- scoring ----------------------------------------------------------------

  def score(agent, human, review = 0)
    (agent * AGENT_WEIGHT + human * HUMAN_WEIGHT + review * REVIEW_WEIGHT).round(2)
  end

  def summarize(events)
    agent = events.count { |e| e["kind"] == "agent" }
    human = events.count { |e| e["kind"] == "human" }
    review = events.count { |e| e["kind"] == "review" }
    { "agent" => agent, "human" => human, "review" => review, "score" => score(agent, human, review) }
  end

  def rolling(scores, n = 10)
    last = scores.last(n)
    return nil if last.empty?
    (last.inject(0.0) { |a, b| a + b } / last.size).round(2)
  end

  # --- stop-hook loop limit ---------------------------------------------------

  def should_block?(attempt, max = MAX_STOP_BLOCKS)
    attempt <= max
  end

  # --- ledger refs ------------------------------------------------------------

  def ref_kind(ref)
    ref.include?("/") || ref =~ /\.(rb|rake|yml|erb|haml|slim)\z/ ? :path : :symbol
  end

  def parse_symbol(ref)
    m = ref.match(/\A([A-Z][\w:]*)(?:[#.](\S+))?\z/)
    m ? [m[1], m[2]] : [ref, nil]
  end

  def stale_refs(refs, path_exists, symbol_found)
    refs.reject do |r|
      if ref_kind(r) == :path
        path_exists.call(r)
      else
        const, meth = parse_symbol(r)
        symbol_found.call(const, meth)
      end
    end
  end
end
