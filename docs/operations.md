# Operations: GPU pods, spend guardrails, and monitoring

The pipeline rents GPU pods (RunPod in this deployment) for training and scoring. Cloud
GPUs bill by the hour whether or not they are doing work, and an autonomous multi-agent
system with API access to a billing account needs hard structure around that. Every rule
here was paid for; the receipts are in [lessons.md](lessons.md).

## Provisioning is centralized to one role

**Only tech-support runs pod-create and pod-terminate, the two billing actions.** Every
other lane may request, run its workload, and monitor; it never creates or kills a pod.
One gate stands between "a lane wants compute" and "money is burning".

The flow:

1. **A lane files a pod request** (`ch pod-request`, which scaffolds the full preflight
   bundle as an ask to tech-support): the job, the named bottleneck resource, **CPU/system
   RAM and GPU VRAM as two separate line items** (never one conflated "RAM" number), the
   box spec, data-presence gates, a smoke command with evidence, an ETA, and projected
   cost. tech-support provisions only against a complete bundle.
2. **tech-support verifies the box** (cgroup memory read, `nvidia-smi`, disk), launches
   it, registers it on the bus, and hands the lane SSH.
3. **The lane owns the workload**: launches its job, arms a failure-emitting monitor,
   pulls and checksums artifacts. It does **not** terminate: when artifacts are verified
   local, it notifies tech-support, who tears down and confirms zero pods remain on the
   account.
4. **Kill authority is tech-support's alone**, exercised unilaterally on a burn-ceiling
   breach or an idle-hardware finding. A lane that believes its own pod must die says so;
   it does not reach for the API.

## The spend cap is the authorization boundary

The billing account carries a hard hourly spend limit, sized to the largest routine
configuration (in this deployment: two consumer GPUs). tech-support provisions anything
under the cap on its own authority. Anything over it is hard-blocked at the API and
requires the human operator to raise the cap personally, routed through the researcher.
More compute than the cap allows means the operator gets consulted, never that the limit
gets bumped quietly.

On top of the cap:

- **A burn ceiling** (aggregate running-pod dollars per hour) acts as a tripwire, not a
  budget: burn above it means a job is *wrong* (almost always CPU/RAM work rented on a GPU
  box) and gets redone right-sized, not paid for. A live burn-watch catches a breach
  within about two minutes and **emails the operator directly** (throttled, via a
  server-side mail identity), so a runaway pod reaches a human even when no session is
  watching a terminal.
- **Spend reporting:** any result that consumed pod time states its spend, computed from
  the billing API (`ch spend`), not hand-estimated. `ch spend` also diffs the live account
  against the bus registry to flag the forgotten-pod case: a pod billing but registered
  nowhere.

## The pod registry: nobody abandons hardware silently

The instant a pod launches: `ch pod-up <lane> <podId> --monitor <taskid> --eta <hours>`.
The instant it stops: `ch pod-down`. From that registration the shared board can flag:

- **ABANDONED POD**: a registered pod whose lane has gone silent past a threshold
  (default 90 minutes). Outranks every other board state.
- **BARE**: a pod registered with no monitor recorded, a visible nudge that a billing box
  has no watcher.
- **OVER-ETA**: a pod billing past its own declared runtime envelope.

## Monitoring discipline

- **A running pod must have a live, progress-based monitor**, armed the moment the job
  starts, with its task id recorded. The filter must emit on **failure states** (died,
  OOM, GPU lost, SSH fail), not only on success: a filter that fires only on DONE tells
  you nothing when it matters, and a dead monitor's silence is identical to a healthy
  one's. Prove the alarm can fire before you trust it.
- **Kill the monitor the instant the pod dies.** Monitor loops survive context compaction
  invisibly and will poll a terminated pod forever. A periodic stuck-sweep catches the
  ones that slip through.
- **Idle is waste.** Stop the pod the moment work ends; do analysis and writeup with zero
  pods running; after any long operation, query the billing API and confirm zero pods
  remain ("I think I stopped it" is not confirmation).

## Lifecycle hard rules

1. **Preflight before any launch:** a GPU tensor op, disk and RAM checks, data-presence
   gates, and a two-minute exact-command smoke test **including the scoring step**. If
   there is a chance the pod won't fire with the setup, don't run it.
2. **Verified pull before stop.** These pods have no volume: stop or terminate wipes the
   disk. Checksum every pulled artifact against the remote **before** stopping, because
   after the wipe the source is gone and a silently truncated pull becomes permanent,
   undetectable loss. And pull for the *next* pre-registered step, not just the current
   read: a teardown that grabs today's numbers and leaves tomorrow's inputs on the wiped
   disk is still a miss.
3. **Right-size to the bottleneck, not the pipeline.** A data rebuild is CPU/RAM-bound
   and uses zero GPU; run it on a CPU box. Within minutes of any run, check `nvidia-smi`:
   idle GPUs on a GPU box mean you are on the wrong instance.
4. **Wedged vs slow: sample CPU time twice, seconds apart**, before killing anything.
   Advancing CPU time is progress, no matter how stale the log looks. Only flat CPU time
   plus no GPU utilization justifies "wedged". Never terminate on an ambiguous signal; a
   pessimistic miscall that kills a healthy multi-hour run costs more than one more
   sample.
5. **A pod that looks dead often isn't.** A wrong SSH key produces the same permission
   error as a dead box. Retry with the known-correct provisioning key before declaring
   death, and never terminate on a single failed connection.
