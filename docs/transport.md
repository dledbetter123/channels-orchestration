# Why the transport looks like this

A design justification for the messaging layer: publish/subscribe semantics delivered by
direct write, with a polling notifier. Every number in this document is measured on a live
deployment, and the places where the design is weak are named rather than omitted.

## The constraint that inverts everything

Conventional messaging systems optimize for **latency** and **idle cost**. Deliver fast, cost
nothing when quiet. Mach ports, XPC, `notifyd`, and every broker in common use are shaped by
those two goals, and they converge on the same answer: event-driven delivery, blocking waits,
no timer loops, on-demand activation.

This system has a different cost function, because **the subscribers are language-model
sessions**.

When a message reaches an agent here, the agent does not run a 200-microsecond callback. It
is re-invoked as a **full-context turn**: its entire working context is re-read, the message
is reasoned about, and tokens are spent proportional to the size of that context, not the
size of the message. On the deployment this document draws from, sessions run at 150k to 220k
tokens of context. A one-line message costs the same wake as a 3,000-word one.

So the quantity to minimize is not latency and not idle cost. It is **wakes per unit of
delivered information**. That single substitution explains most of what follows, including the
parts that look wrong by conventional standards.

Anyone evaluating this architecture should check whether their subscribers have that property.
If the subscribers are ordinary processes, most of the reasoning below does not transfer and a
conventional broker is the better answer.

## Three layers, three different answers

The system is often described as "pub/sub" or "polling" as though those were competing
descriptions of one thing. They are descriptions of different layers, and it is worth being
precise about which is which.

| Layer | Model | Mechanism |
|---|---|---|
| Addressing and fan-out | **Publish/subscribe** | Named channels as topics; per-agent subscription lists on disk; the publisher resolves recipients at publish time |
| Delivery | **Push** | The publisher's own process appends directly into each recipient's mailbox file, synchronously, before it returns |
| Notification | **Poll** | Each session runs a loop that compares its mailbox file against what it last saw, and emits new lines |

The delivery layer being push, executed by the sender, is what makes the receipt honest. When
`send` prints `delivered to: auditor writer`, the write has already happened. A send to an
agent that does not subscribe to that channel fails loudly as `UNDELIVERABLE` rather than
being silently dropped, because the recipient set is computed and checked at publish time
rather than inferred later.

## Why the notification layer polls

The honest answer is not "polling is simpler." It is that **the poll is not in the data path,
and the model is not in the poll.**

The loop is a shell process running `sleep`. It costs no tokens and involves no inference. A
session is invoked only when the loop actually finds a new line. So the usual argument against
polling, that it burns resources asking a question whose answer is almost always "nothing,"
does not apply: the expensive resource here is model invocation, and the poll never triggers
one on an empty tick.

That leaves polling accomplishing exactly two things, and it is worth being strict about the
list, because a design justified by benefits it does not deliver is a design nobody can
maintain.

**1. It is the only thing that converts a write into a turn.** Every other property of the
system survives without it. The sender computes recipients and writes their mailboxes;
durability is the file; ordering is the append. What does not survive is attention. An agent
session is otherwise inert, and the mailbox could be correct and unread indefinitely. Nothing
else in the system turns on-disk state into an agent doing something.

**2. The running loop is the liveness token.** This is load-bearing and easy to miss. "Who
currently holds this role" is answered by "whose watch process is alive." Leader versus worker
arbitration, the stuck-lane sweep, the resume guard that refuses a cross-session takeover, and
the live-instance roster all key off it. In one recorded case a joining session was briefed by
its leader, given a work slice, and never armed its watch; it sat for two days receiving
nothing, and the only reason that was detectable is that a watch process is a thing you can
probe. Absent a live loop, the role model has no ground truth.

**What polling does not accomplish here:** delivery, durability, ordering, or guaranteed
receipt. A missed tick is survivable *because* the poll is not load-bearing for correctness.
The notification is deliberately lossy and the queue is durable. A lane can lose its watch for
an hour, re-arm, and lose nothing, because anything the stream failed to announce is still
sitting in the mailbox marked unread.

## Why not event-driven

The blocking-wait primitives are available. On this platform a watch could use a kernel file
event and fire the instant a mailbox is written, with no timer at all. That is the textbook
correct answer and it is the wrong one here, for a reason that is measurable rather than
philosophical.

**Event-driven delivery maximizes wakes.** It fires once per write, which is exactly the
quantity being minimized. A polled tick, by contrast, emits every line accumulated since the
last tick in a single batch, which the notification layer delivers as one wake regardless of
how many messages it contains. In principle, therefore, the interval is a debouncer and going
event-driven would remove it.

**In practice, at this deployment's traffic, it debounces almost nothing.** Measured across
858 delivery events and 1,501 consecutive per-recipient arrivals:

| Poll interval | Deliveries coalesced into a prior wake |
|---|---|
| **20s (default)** | **3%** |
| 60s | 10% |
| 120s | 25% |
| 300s | 55% |
| 600s | 75% |

Per-recipient median inter-arrival gaps run 229 to 486 seconds. At that spacing a 20-second
window catches essentially nothing, so the default configuration is, empirically, one wake per
message: the same behavior an event-driven watch would produce, at the same cost.

This is stated plainly because it is the strongest available argument *against* the current
default, and a justification that suppresses it is worth less than one that does not. **The
correct reading is that polling is defensible and the chosen interval is not.** The interval
is a free lever that was never turned. Raising it to 300 seconds is one environment variable
and buys a 55% reduction in wakes.

The reason the lever is not simply pulled is a protocol question rather than a technical one:
it delays every lane's mail by up to five minutes, which is a behavior change visible to every
participant, and on this deployment that decision belongs to the coordinating role rather than
to whoever owns the plumbing.

## Explicit coalescing, and why it is not redundant

A digest mode holds new mail until the mailbox has been quiet for a configured window, then
emits one block. Measured on 60 consecutive deliveries to one recipient: **62% fewer wakes at
a 5-minute window, 85% at 10 minutes.**

Given the interval table above, this looks redundant, and mostly it is. It survives for one
specific reason worth preserving in any reimplementation: **the blocking round-trip must stay
immediate.** When an agent files a request and explicitly waits for the answer, that wait runs
in its own process and is deliberately not debounced. A raw interval increase cannot express
that distinction, because it slows every path uniformly. The digest can, and a protocol-change
event flushes it instantly for the same reason.

The general principle: **coalescing must be selective about what it is allowed to delay.**
Batching that also delays a synchronous wait converts a cost optimization into a deadlock
risk.

## Why the log is a git repository

Delivery does not travel through git. The mailbox write hits the filesystem first and is
committed afterward. Git supplies four properties that a message queue does not:

- **Permanence and attribution.** Every message is a commit. The commit hash is the message
  id, referenced by replies, so "which message closed this request" is answerable years later
  by a reader with no access to the running system.
- **A conversation history that is also a build history.** The same log carries the messages
  and the artifacts they were arguing about.
- **Cold-start reconstruction.** A fresh participant reconstructs state by reading, not by
  querying a live service. There is no broker whose in-memory state is the truth.
- **Auditability without instrumentation.** Every measurement in this document was computed
  from the log after the fact. Nothing had to be instrumented in advance, because the log was
  already the complete record.

The tradeoff is real and is discussed below.

## Known weaknesses

**No demand activation.** A participant must already be running and have armed its watch to be
notified. Compare launchd, where the service need not be alive to be reachable: port activity
brings it up. There is no equivalent here, and the failure mode is exactly the one that
implies, a session that never arms receives nothing while looking, from the outside, like a
colleague who is simply quiet. The mailbox durability limits the damage, since the messages are
waiting whenever it does arrive, but the latency is unbounded.

**One working tree, many concurrent writers.** Because the log is a git repository and the
participants share it, the git index is shared mutable state. In one recorded incident a
participant's staged message was swept into a different participant's commit, under that
participant's subject line, and was never delivered, because a commit without a path
restriction commits whatever is staged. The fix is to scope every commit to its own paths, and
that discipline has to be enforced everywhere rather than at the site where the bug was first
observed: an audit found thirteen such commit sites, not one. **A shared-worktree design makes
"commit only your own paths" a correctness requirement, not a style preference.**

**The default interval is unjustified.** See the table above. It is not harmful, and it is not
buying what it appears to buy.

**Silent-success failure modes are structurally easy here.** Several of the incidents behind
these rules share one shape: an instrument reports success by producing no output. A monitor
whose filter matches only a breach line stays silent when the query itself fails. A backlog
counter that never subtracts resolved items reports a number that cannot be driven to zero, so
it stops carrying information at any value. Both were live in this deployment and both were
found by deliberate testing rather than by observation. The design consequence is a standing
rule: **prove an alarm can fire before trusting its silence, and prove each arm of a
multi-condition check separately, since a composite alarm that rings tells you at least one arm
is live and nothing about the rest.**

## When this architecture is the right choice

**It fits when:**

- Subscribers are expensive to wake, so wake count dominates the cost model.
- The participant count is small, on the order of ten, not thousands.
- Message rates are minutes apart, not milliseconds.
- An auditable, permanent, human-readable record is a first-class requirement rather than a
  nice-to-have.
- Participants come and go, and must reconstruct state by reading rather than by subscribing
  to a live feed.

**It does not fit when:**

- Subscribers are ordinary processes with microsecond callbacks. Then the entire cost argument
  inverts and a conventional broker wins.
- Throughput is high. Git is a poor queue at volume, and a shared working tree is a poor
  concurrency primitive.
- Delivery latency is a real requirement. Everything here trades latency away on purpose.

## The summary defensible in one paragraph

Publish/subscribe semantics, because addressing is one-to-many by topic and senders should not
know subscriber identity. Push delivery executed by the sender, because that makes the delivery
receipt truthful and makes undeliverable addressing loud instead of silent. Polled notification,
because the poll costs nothing when the subscribers are the expensive component, because it is
the only thing that converts a durable write into subscriber attention, and because the running
loop doubles as the liveness signal that the role and leadership model depends on. A git
repository as the log, because permanence, attribution, and cold-start reconstruction were
requirements, not conveniences. **The measured weakness is that the poll interval is doing none
of the coalescing work usually attributed to it, and the honest justification for the current
default is that nobody has needed to change it, not that it was chosen well.**
