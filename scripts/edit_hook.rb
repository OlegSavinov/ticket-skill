# PostToolUse hook (Edit|Write): on lines changed during this ticket, run
#   1. promoted checks from .claude/ticket/checks.yml (any file type)
#   2. RuboCop (.rb/.rake, only if the project has RuboCop)
# Exit 2 feeds findings back to Claude. No-op without an active ticket.
require_relative "hooklib"
H = TicketHooks

input = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError
  {}
end
root = H.root(input)
dir = H.state_dir(root)
state_path = File.join(dir, "state.json")
exit 0 unless File.exist?(state_path)

file = (input["tool_input"] || {})["file_path"].to_s
exit 0 unless File.file?(file) && file.start_with?(root + "/")
rel = file[(root.size + 1)..-1]
exit 0 if rel.start_with?(".claude/")

state = H.read_json(state_path, {})
base = state["base"] || "HEAD"
# shortcut: a pre-existing untracked file has no baseline, so it is skipped entirely; fine
# unless tickets often edit files the user hasn't added to git yet.
exit 0 if (state["untracked_at_start"] || []).include?(rel)
tracked = !H.git(root, "ls-files", "--", rel).strip.empty?
lines = tracked ? H.changed_lines(H.git(root, "diff", "-U0", base, "--", rel)) : nil
exit 0 if lines && lines.empty?

findings = []

checks = begin
  H.read_yaml(File.join(dir, "checks.yml"), [])
rescue Psych::SyntaxError => e
  findings << "Note: .claude/ticket/checks.yml is invalid YAML (#{e.message}); promoted checks skipped. " \
              "Tell the user at the next gate; don't fix it yourself."
  []
end
unless checks.empty?
  hits = H.check_violations(checks, rel, File.readlines(file), lines)
  unless hits.empty?
    H.log_event(root, "agent", "check", "#{rel}: #{hits.size} promoted-check hit(s)")
    findings << "Promoted checks (lessons from past tickets):\n" + hits.join("\n")
  end
end

lock = File.join(root, "Gemfile.lock")
cmd =
  if File.executable?(File.join(root, "bin", "rubocop")) then ["bin/rubocop"]
  elsif File.exist?(lock) && File.read(lock) =~ /^\s+rubocop \(/ then %w[bundle exec rubocop]
  end
# No project RuboCop: don't impose a foreign style on legacy code.
if cmd && rel =~ /\.(rb|rake)\z/
  out, _err, _st = Open3.capture3(*cmd, "--format", "json", "--force-exclusion", rel, chdir: root)
  json = begin
    JSON.parse(out)
  rescue JSON::ParserError
    {} # rubocop itself broke (config/version); don't block edits on tool trouble
  end
  offenses = H.filter_offenses(json, lines)
  unless offenses.empty?
    H.log_event(root, "agent", "rubocop", "#{rel}: #{offenses.size} offense(s)")
    findings << "RuboCop offenses on lines you changed. Fix these only; leave legacy offenses alone.\n" +
                H.format_offenses(rel, offenses)
  end
end

exit 0 if findings.empty?
warn findings.join("\n\n")
exit 2
