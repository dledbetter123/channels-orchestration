# Roles and the chain of command

## One line to the operator

The human operator drives the system through exactly one agent: the **researcher**. This
is the load-bearing org-design decision. Without it, four agents each ping the operator
independently and the operator becomes the message bus.

- **The researcher is the lead.** Direction, framing, and priority are theirs. They
  consult the auditor continuously, then direct the writer and builder.
- **Workers do not go to the operator; they consult the researcher.** If the auditor,
  writer, or builder thinks something needs an operator decision, they take it to the
  researcher, who escalates only if it actually needs the operator.
- **Operator directives can arrive off the bus** (the operator may instruct any agent
  directly in its own session, with no on-bus record). Those are real; follow them, but
  loop the researcher in so the lead never loses the thread. If an off-bus directive seems
  to conflict with a standing one, confirm with the operator before publicly challenging
  it: the operator has context the bus does not.

## The auditor is a mid-brain, not a rubber stamp

The auditor has two distinct interaction modes, and the distinction is first-class in the
protocol:

- **Verdict mode** (terminates): on a finished claim, the auditor replies CONFIRMED /
  REFUTED / UNDERDETERMINED plus the falsifier that decided it, and the ask closes.
- **Consult mode** (loops): the researcher brings *forming* work (a half-shaped direction,
  not a finished claim) with a subject prefixed `CONSULT:`. Each turn replies to the prior
  message and re-asks the other party, so the thread ping-pongs and the shared views always
  show whose move it is. The researcher closes the loop with a final reply carrying no new
  ask.

Consult-mode rule: **a challenge is incomplete without a grounded next step.** When the
auditor pushes back on forming work, it must pair the pushback with how to iterate (what
would make the idea hold, or how to kill it cleanly), drawn from the same evidence base it
audits from. A bare "REFUTED" with no path forward is a verdict, not a guide, and a
mid-brain that only demolishes cannot loop.

Authority does not move: the auditor's advisory scope spans claims, directions, and ideas,
but the researcher stays the decider.

## The writer owns long-form static writing

Study guides, onboarding notes, explainer docs, reference material: all of it goes to the
writer, on the researcher's directive (the researcher supplies substance and accuracy
anchors). This is a throughput rule, not a vanity label: delegating static prose keeps the
researcher on research. Boundary: short bus messages, handoffs, and live analysis stay with
whoever owns them.

Two placement norms ride along:

- **Study material vs operational truth.** The external knowledge surface (a Notion
  workspace in this deployment) carries only material the operator should *learn*:
  concepts, definitions, worked examples. Live task status, pending numbers, and lane
  state stay on the bus and in ledgers, the one place that is versioned, addressed, and
  audited.
- **Figures are contracted, not described.** When a document needs a chart or diagram, the
  writer does not narrate it in prose. It opens an ask to the builder stating exactly what
  the figure must show, and the builder renders a real image and replies with the artifact
  path. A described graph is strictly worse than a drawn one.

## tech-support owns the flow, not the work

tech-support maintains the bus (CLI, hooks, protocol) and fixes defects autonomously, but
routes bus *governance* changes (subscription topology, protocol policy) through the
researcher, because those change how the research runs. Its distinctive duties:

- **Active flow assurance.** tech-support may initiate 1:1 check-ins with any lane to
  verify it has the current protocol version, learn what it has in flight, and confirm
  delivery is working. Route-by-kind rule: questions about the *flow* (delivery,
  addressing, pod registration, "did my message land") go to tech-support; questions about
  the *work* (what to run, whether a claim holds) go to the researcher.
- **Stuck sweeps.** All lanes run as one OS user on one machine, so tech-support can see
  orphaned watcher loops and monitors polling dead pods. A periodic sweep (`ch stuck`)
  surfaces the two mechanically-reliable cases and reaps or escalates. A possibly-wedged
  *computation* is a judgment call, not a mechanical fault: sample CPU time twice, and
  take kill-or-wait to the researcher. Never unilaterally kill a possibly-live run.
- **Sole pod authority.** Only tech-support creates or terminates billing GPU pods (see
  [operations.md](operations.md)).
- **Nobody else touches the plumbing.** If delivery misbehaves, report it and keep doing
  your own work. This rule exists because two agents once edited the same hook file
  simultaneously, neither aware of the other, precisely because nobody owned it.

## The ops lane

The operator broadcasts on `ops`. Everyone subscribes; no agent publishes there. If an ops
message is in your poll, you read it before anything else.
