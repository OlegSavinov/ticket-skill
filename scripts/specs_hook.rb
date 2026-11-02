# Stop hook: run the specs relevant to files changed since the ticket started.
# Failing specs block the stop (exit 2) up to MAX_STOP_BLOCKS times in a row, then hand
# back to the user. Skips when nothing changed since the last green run.
require_relative "hooklib"
require "digest"
H = TicketHooks

input = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError
  {}
end
root = H.root(input)
state_path = File.join(H.state_dir(root), "state.json")
exit 0 unless File.exist?(state_path)

state = H.read_json(state_path, {})
base = state["base"] || "HEAD"
untracked = H.git(root, "ls-files", "--others", "--exclude-standard").split("\n") - (state["untracked_at_start"] || [])
changed = H.git(root, "diff", "--name-only", base).split("\n") + untracked
specs = H.relevant_specs(changed, ->(p) { File.exist?(File.join(root, p)) })
exit 0 if specs.empty?

untracked_rb = untracked.select { |p| p.end_with?(".rb") && File.file?(File.join(root, p)) }
fingerprint = Digest::SHA1.hexdigest(
  H.git(root, "diff", base) + untracked_rb.map { |p| p + File.read(File.join(root, p)) }.join
)
exit 0 if state["green"] == fingerprint

cmd = File.exist?(File.join(root, "Gemfile")) ? %w[bundle exec rspec] : ["rspec"]
out, st = Open3.capture2e(*cmd, *specs, chdir: root)

if st.success?
  state["green"] = fingerprint
  state["blocks"] = 0
  H.write_json(state_path, state)
  exit 0
end

attempt = state["blocks"].to_i + 1
H.log_event(root, "agent", "specs", "attempt #{attempt}: #{specs.join(' ')}")
if H.should_block?(attempt)
  state["blocks"] = attempt
  H.write_json(state_path, state)
  warn "Relevant specs failed (attempt #{attempt}/#{H::MAX_STOP_BLOCKS}). Fix them before finishing.\n" \
       "Ran: #{cmd.join(' ')} #{specs.join(' ')}\n\n#{out.lines.last(60).join}"
  exit 2
end

state["blocks"] = 0
H.write_json(state_path, state)
puts JSON.generate("systemMessage" => "/ticket: relevant specs still fail after #{H::MAX_STOP_BLOCKS} attempts. Stopped so you can decide.")
exit 0
