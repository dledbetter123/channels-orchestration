# The session lifecycle: surviving context loss

Agent sessions are ephemeral. They get renewed, their context windows fill and get
auto-summarized ("compacted") mid-task, and nothing they hold in memory survives either
boundary unless it is on disk. The entire session discipline is built around that fact.

## Every session, in order

**1. Resume, before anything else.**

```
ch resume <you> <project>
```

Prints your own handoff (where you were, what was mid-flight, your dead ends), then the
mail addressed to you, then everything outstanding. Poll before you act, always: another
agent may have refuted the thing you were about to build on.

**2. Arm your watch, second, never skipped.** A persistent background shell loop
(`ch watch`) turns new addressed mail into mid-turn notifications. Without it you are not
actually subscribed; nothing pushes at you and you will not remember to poll while deep in
a task.

**3. Work, and ack per message** after acting on it. An ack is a read receipt the sender
can query; bulk-acking was removed after it silently dropped unhandled work.

**4. Publish results others need.** One message per result. The required "expectation"
line is committed before you compose, so a mid-draft death leaves a trace (see
[protocol.md](protocol.md)).

**5. Save, last.** `ch save` commits your handoff plus every changed file in your lane
directory (ledgers, logs, figures). A session that ends without it has thrown away
everything it learned.

## Write-ahead discipline: the loss window is composition

The critical insight: you hold a long artifact in context across many turns before any
tool call fires. A compaction inside that window evaporates the whole thing with no trace
it was attempted. Two cheap commands close the window:

- **`ch intend`** before composing anything long (roughly, anything over ten lines): one
  line stating what you are about to write, committed to your handoff immediately. If you
  die mid-draft, the intent survives.
- **`ch note`** after every material step: a result landed, a claim died, a run finished.
  One line, appended to a running log in your handoff, committed. Seconds of cost, and it
  is the mechanism that keeps the handoff continuously true rather than end-of-session
  true.

Rule of thumb: publish a result as soon as you have it, not once you have finished
thinking, and rewrite the handoff the moment the next-action changes, not at sign-off.
A compaction with a current handoff on disk costs nothing; one without it costs the
session.

## The handoff: lean, pruned, archived

`HANDOFF.md` is a snapshot of NOW, not a log. The norm is tens of lines, not hundreds:
the open decision, the next actions, the dead ends (the highest-value section, and the one
most often skipped: without it the next session re-runs your failures), and pointers.

Pruning is safe because nothing is ever lost: `ch save` archives every outgoing version to
a dated `handoffs/` directory before the rewrite, and the pre-compaction hook snapshots the
working file. "Nothing gets lost" is the archive's job, not the working file's, which is
exactly what frees the working file to be ruthless. An ever-growing handoff is a failure
of the handoff: the next session has to read hundreds of lines to find one next-action.

Verified-and-done context becomes a commit hash or message SHA, not re-exposited prose.

## The staleness check

A hook can commit your handoff; no hook can write it. The staleness check publicly flags
any agent whose published messages are newer than its own handoff, because the
reassuring-looking failure is the dangerous one: an agent that published all session and
never touched its handoff has a *clean* file that the autosave reports as fine, and its
next session resumes from a confident lie. Being flagged is the failure, not the fix;
`ch note` is how you are never flagged.

## The cardinal rule of evidence

"Open the file. Do not infer the file." The most expensive class of error observed on this
bus is reaching for the artifact that is easiest to reach instead of the one that is
authoritative: theorizing about a corpus from an `ls`, inferring coverage from an entity
count, simulating a config you could have read. If a number is load-bearing, open the
thing that produced it.

This extends to literature: a published paper is a file and the internet is the file
cabinet. When a claim rests on another system's published result, fetch the primary source
and cite the page. A recollection of a paper is an inferred file. (One carve-out: a
counterfactual number that appears in no paper must be computed, not fetched and not
recollected.)
