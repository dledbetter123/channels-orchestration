# Lessons: the incidents behind the rules

Nearly every rule in this protocol is a scar. This page collects the failure modes that
shaped the design, because "here is the rule" persuades far less than "here is what
happened without it". Names of datasets and dollar figures are from the real research
program this bus ran.

## Coordination failures

**The buried writer.** One agent received 112 messages, 93 of them as one of three CC'd
recipients. It learned to skim its own inbox, which is how an inbox dies. Result: empty
`subscribers:` is refused, three-plus recipients prints a warning, and "FYI" traffic was
pushed into ledgers and handoffs that every lane already reads.

**The undelivered ask.** A blocking ask sat in the outstanding-work view for a day, aimed
at an agent that was not subscribed to the sender's channel and so never received it.
Result: sends to non-subscribers now shout `UNDELIVERABLE`, and the norm is "never assume
delivery, check".

**The bulk-ack that dropped work.** An early "mark all read" cursor advanced past messages
that had been seen but not acted on, silently. Result: three-state mailboxes (unread /
read / acked), acks per message only, and the deliberate choice that an unhandled message
nags forever rather than disappears.

**Two agents editing the same hook.** Before the bus had an owner, two agents edited the
same hook file simultaneously, neither aware of the other. Result: tech-support exists,
owns all plumbing, and everyone else reports defects instead of fixing them.

**The dual leader.** Two sessions raced one vacant leadership slot on the same role; both
promoted; each believed it was sole leader. Result: the watch slot records the arming
session's identity, a second racing resume is refused with a distinct exit code, and a
takeover requires either the incumbent's standdown or an explicit force flag. The
boundary was drawn deliberately: a genuinely vacant slot stays claimable by anyone,
because the guard's job is to stop races, not to encode operator intent. When claims
still conflict, the operator rules and the record is corrected on the bus.

**Folklore is not protocol.** Norms that lived in one agent's memory, or in an old
message treated as policy, never propagated. Result: every persistent rule must live in
the shared, versioned protocol document, and changes ship as versioned bumps with
major/minor severity (severity exists because when every trivial edit re-staled everyone,
lanes learned to skim the one warning that mattered).

## Context-loss failures

**The retconned hypothesis.** Without a written prediction, a surprising result looks
expected in hindsight and the information in the surprise is destroyed. Result: intent is
committed before composition (the required expectation line on every message; write-ahead
`ch intend` for anything long).

**The confident stale handoff.** An agent published all session, never touched its
handoff, and the autosave hook truthfully reported "nothing to commit". The next session
resumed from a clean, confident, out-of-date file. Result: the staleness check compares an
agent's published messages against its own handoff and flags the mismatch publicly, by
name.

**The uncommitted ledger.** A lane's verdict record rode about 35 iterations uncommitted
while every save reported success, because the save only swept the handoff. Result: save
sweeps the whole lane directory.

## Money failures

**The 8x A100 rebuild.** A CPU/RAM-bound data rebuild ran on an 8-GPU box at $286/day
with 7 of 8 GPUs at 0% utilization, because a system-RAM need was chased through the GPU
catalog. Result: the burn ceiling as a tripwire (a job above it is wrong and gets redone
right-sized, not paid for), CPU RAM and GPU VRAM as mandatory separate line items in every
pod request, and an early `nvidia-smi` check in every run.

**The idle fleet.** Roughly $8-10 of a $20 budget burned on pods sitting idle during
analysis, and later a $125 idle-GPU incident. Result: provisioning centralized to one
role, "analysis happens with zero pods running", and teardown the instant a lane
finishes.

**The forgotten-pod scenario.** The billing account auto-recharges, so a wedged or
forgotten pod bills forever with no wall to stop it. Result: the bus registry is diffed
against the live billing account, aggregate burn is watched continuously, and a
burn-ceiling breach emails the human operator directly, reaching them even when no
session is watching a terminal.

## Data-loss failures

**The truncated pull.** A file transfer timed out silently; the archive was corrupt; the
source had already been wiped by pod teardown. Result: verified pull before stop, always:
checksum against the remote while the remote still exists.

**The wiped next step.** A teardown pulled the current analysis inputs and terminated,
destroying the per-node score vectors a pre-registered *next* step needed (recoverable
only because the run was deterministic). Result: pull for the next consumer, not just the
current read.

**The healthy pod terminated as dead.** A wrong SSH key produces exactly the same
permission error as a dead machine; a healthy pod with unrecovered results was terminated
on that signal while a background monitor was authenticating fine the whole time. Result:
retry with the known-correct key before declaring death, and never terminate on a single
ambiguous signal.

## Monitoring failures

**Silence is not success.** A monitor whose filter only fires on DONE is indistinguishable
from a dead monitor. A process-grep that matches its own SSH command line reports "still
running" forever. Result: monitors must emit on failure states, watch for explicit
completion or failure lines rather than process absence, and prove the alarm can fire
before trusting it.

**Wedged vs slow.** A run whose output file had been stale for 16 minutes was nearly
killed as "hung" while its CPU time was advancing the whole time. Result: sample
accumulated CPU time twice, seconds apart; advancing CPU time is progress regardless of
log staleness; only flat CPU time plus idle GPU justifies a kill, and even then the
decision goes to the lead, not the observer.

## The meta-lesson

Autonomy scales only as fast as its guardrails. Each agent here is individually capable;
what makes the *system* work is that the expensive actions (publishing, spending,
terminating, taking over a role) are gated by cheap mechanical checks that fail loudly,
and that every failure gets encoded back into the shared protocol instead of into one
agent's memory. The bus is append-only because trust is rebuilt from the record, not from
recollection.
