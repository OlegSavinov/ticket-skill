# UserPromptSubmit hook: detect human corrections during an active ticket.
# Logs a human event when the user's message contains a correction or points out
# something the agent missed. Answering questions or giving preferences is not logged.
#
# Exit 0 always (never block user input), but log to run.jsonl when correction detected.
require_relative "hooklib"
require "json"
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
exit 0 unless state["ticket"] # no active ticket

message = (input["prompt"] || input["message"] || "").to_s.strip
exit 0 if message.empty?

# Detect the current gate from state (set by the agent at each gate)
gate = state["current_gate"] || "unknown"

# --- Classification ---

# Simple approvals and answers: don't log
APPROVALS = [
  /\A(ok|okay|k|yes|yep|yeah|sure|go|lgtm|looks good|approved?|proceed|continue|do it|ship it|sounds good|perfect|great|good|fine|agreed?|correct|right|exactly|👍|✅|🚀)\s*[.!]?\z/i,
  /\A(go ahead|carry on|move on|next|that'?s (fine|good|correct|right))\s*[.!]?\z/i,
  /\A[ABCabc1-9]\s*[.!]?\z/, # single-letter/number answers to multiple choice
]

# Strong correction signals: these indicate the agent made a mistake
CORRECTION_SIGNALS = [
  # Explicit disagreement
  /\b(no[,.]|nope|wrong|incorrect|that'?s not|not quite|not right)\b/i,
  # Pointing out mistakes
  /\b(mistake|error|bug|broken|fails?|crashed?|doesn'?t work)\b/i,
  # Missed something
  /\b(forgot|missing|missed|overlooked|skipped|ignored|left out)\b/i,
  # Correction phrases
  /\b(actually[,.]|instead[,.]|rather[,.]|should be|needs? to be|supposed to)\b/i,
  /\b(that should|this should|it should|you should have)\b/i,
  # Explicit fix requests
  /\b(fix (this|that|it)|change (this|that|it) to|update (this|that|it) to)\b/i,
]

# Check if it's a simple approval/answer
is_approval = APPROVALS.any? { |re| message =~ re }
exit 0 if is_approval

# Check for correction signals
has_correction = CORRECTION_SIGNALS.any? { |re| message =~ re }
exit 0 unless has_correction

# Truncate message for the log (first 200 chars)
summary = message.length > 200 ? message[0, 197] + "..." : message
# Escape quotes for the log
summary = summary.gsub('"', "'").gsub("\n", " ").squeeze(" ")

H.log_event(root, "human", gate, summary)

# Output a note so the agent knows feedback was logged
puts JSON.generate(
  "systemMessage" => "[feedback logged: human/#{gate}] Remember to address this feedback and consider it for the retro."
)

exit 0
