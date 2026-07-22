---
name: runpod-ops
description: Operate RunPod GPU pods safely — SSH access (correct keys, proxy form, ports), GraphQL API (list/terminate/balance), preflight protocol before launch, artifact-pull-before-stop discipline, and the known failure modes. Use whenever launching, connecting to, monitoring, or tearing down a RunPod pod.
---

# RunPod operations (hard-won, 2026-06 through 2026-07)

## Credentials and access (get these RIGHT first)

- **API key:** `~/.runpod/config.toml` (`apikey = rpa_...`). Do not hunt the keychain; it is not there.
- **SSH identity: `~/.runpod/ssh/runpodctl-ssh-key`.** This is THE key pods are provisioned with when
  launched via runpodctl/CLI. NOT `~/.ssh/runpod_ed25519`, NOT `~/.ssh/id_ed25519`.
  - Failure signature of the wrong key: `Permission denied (publickey,password)` — which looks IDENTICAL
    to a dead/reclaimed pod. **2026-07-12 incident:** this misdiagnosis ("pod SSH broke") led to
    terminating a healthy pod with unrecovered results on it, while a background monitor was
    authenticating fine the whole time with the correct key. Before declaring a pod dead, try the
    runpodctl key explicitly: `ssh -i ~/.runpod/ssh/runpodctl-ssh-key -o IdentitiesOnly=yes ...`.
- **CLI-launched pods need `PUBLIC_KEY` in env** at creation or SSH is never installed.

## Connecting

- **Direct (preferred):** `ssh -i ~/.runpod/ssh/runpodctl-ssh-key -p <publicPort> root@<ip>`.
  Get current ip/port from the API (below) — **a pod restart changes the public port**, so never trust a
  cached port after any restart.
- **Proxy (fallback):** `ssh -tt -i ~/.runpod/ssh/runpodctl-ssh-key <podId>-<hex>@ssh.runpod.io`.
  - Requires a PTY: plain command exec fails with "Your SSH client doesn't support PTY"; use `-tt`.
  - Bare `<podId>@ssh.runpod.io` (no `-<hex>` suffix) is rejected.
  - The proxy's internal hop (100.65.x.x:2002) is flaky and can time out even when auth succeeds.
    Direct SSH with a fresh port from the API is more reliable.
- **For nohup launches over SSH use `ssh -n`** (otherwise the remote job can die with the session).
- **zsh does not word-split unquoted vars** — flags packed in a var need `${=VAR}` or an array.
- **`pkill -f <pattern>` self-matches the launching SSH shell** if the pattern appears in the ssh
  command line (exit 255, run dies). Avoid pkill -f in launch one-liners.
- **`pgrep -f <pattern>` self-matches the same way — and this one fails SILENTLY, which is worse.**
  A completion monitor that decides "job still running" from `pgrep -f 'train.py'` over SSH matches
  its *own* ssh shell (the command line contains `train.py`), so pgrep always finds a match, the job
  looks alive forever, and the completion signal never fires. Silence looks identical to a running
  job — this cost ~1h undetected on the THEIA anchor (2026-07-17). Two fixes, use both:
  - **Bracket the pattern** so it can't match the literal text of the invocation:
    `pgrep -f '[t]rain.py'`. The regex `[t]rain.py` matches the process running `python train.py`,
    but the ssh/pgrep command line contains the literal string `[t]rain.py`, which `[t]rain.py` as a
    regex does NOT match (`[t]` matches `t`, not `[`). Same trick as `ps aux | grep '[p]attern'`.
  - **Watch for a completion LINE, not process absence.** Don't infer "done" from a process
    disappearing — have the job print an explicit end marker (or write a sentinel file) and watch the
    log for it: `tail -f run.log | grep -E 'DONE|Traceback|Error|Killed'`. A positive done/fail
    signal is robust; "the process I was grepping for is gone" is fragile and self-matching. This is
    the "progress-based monitor that emits on completion AND failure" discipline, applied to the
    remote case.

## API (GraphQL) — no runpodctl binary needed

Endpoint: `https://api.runpod.io/graphql?api_key=<key>`, POST JSON `{"query": "..."}`.

- Balance + pods:
  `query{myself{clientBalance pods{id name desiredStatus costPerHr runtime{uptimeInSeconds}}}}`
- Current SSH ip/port:
  `query{myself{pods{id name runtime{ports{ip isIpPublic privatePort publicPort type}}}}}`
  (use the entry with `type=="tcp" && isIpPublic`; privatePort 22 is sshd)
- Terminate: `mutation{podTerminate(input:{podId:"<id>"})}` — returns `{"podTerminate":null}` on success;
  verify with the pods query afterward.

## Provisioning is CENTRALIZED to tech-support (operator directive 2026-07-18, ref 1ab0e75f)

**Only tech-support runs `podCreate` / `podTerminate` — the billing actions. No other lane touches
the RunPod provisioning API, ever.** This supersedes the old pods-free-rein arrangement. It exists
because an all-day, ~$100, self-provisioned E5 rebuild cycled expensive multi-A100 boxes for a job
that used zero GPU; one gate now stands between "a lane wants compute" and "money is burning."

- **A lane that needs compute files a POD REQUEST to tech-support** (`ch pod-request <project>
  <lane> <slug>` scaffolds it; `asks: tech-support`) carrying the full preflight bundle: job;
  bottleneck resource named; **CPU/system-RAM and GPU-VRAM as TWO SEPARATE line items** (operator
  directive 2026-07-18 — never one conflated "RAM" number); box spec; gates; smoke command +
  evidence; ETA; projected cost. tech-support provisions ONLY against a complete bundle.
  - **CPU-RAM vs GPU-VRAM must never be conflated.** They are different resources on different
    hardware. A **system-RAM** need is satisfied by a high-RAM CPU box and does NOT justify renting
    a GPU; **GPU-VRAM** is the memory the model+batch need on the card. The 8×A100 fiasco was
    exactly this conflation — a CPU-RAM need (~1TB system RAM for a rebuild) chased through the
    GPU-box catalog, renting 8 idle A100s for their host RAM. Every spec states both numbers
    separately, and the box is chosen against the **binding** one. Name a GPU only when GPU-compute
    or GPU-VRAM is the bottleneck; if the job is CPU/RAM-bound, the answer is a CPU box.
- **tech-support** verifies the box (cgroup read, `nvidia-smi`, disk), launches it, registers it
  (`ch pod-up --monitor --eta`), and hands the lane SSH. The requesting lane owns the WORKLOAD —
  launches its job, arms its failure-emitting monitor, pulls+checksums artifacts — but **does NOT
  terminate**: when artifacts are verified local, it notifies tech-support, who tears down and
  confirms zero pods.
- **Kill authority:** tech-support may kill any pod unilaterally on a burn-ceiling breach or
  idle-hardware finding (that IS the flow-guard working). A lane that believes its own pod must die
  says so to tech-support; it does not reach for the API.
- **The $1.50/hr authorization boundary is a POLICY, enforced by AGENTS, not by the account
  (operator directive 2026-07-18, enforcement corrected by the operator 2026-07-21).**
  tech-support provisions any right-sized configuration under **$1.50/hr** on its own authority (one
  or two 4090s ~$1.38/hr, or a single GPU under the line). **Anything over $1.50/hr requires the operator's
  explicit authorization**, routed through the researcher.
  - **CORRECTION, and read it before you reason about spend: the earlier "hard-blocked at the API"
    claim was WRONG and is withdrawn.** The RunPod account limit is **$80/hr and CANNOT be lowered**
    — the user API key lacks the scope, and the operator has confirmed the account value is not
    adjustable at all. There was never a $1.50/hr vendor block, and there will not be one.
  - **What that means operationally:** nothing at the vendor stops a runaway before **$80/hr**. The
    entire defense is three soft, agent-side controls — tech-support's provisioning gate, the
    **$2/hr burn ceiling** caught within ~2 minutes by the burn-watch, and the throttled email that
    reaches the operator with no session running. Treat every one of them as load-bearing; a missed
    burn-watch is not a redundancy failure, it is the failure.
  - **A "raise the cap" request is now meaningless** — there is no cap to raise. Over-policy compute
    is a DECISION the operator makes, not a setting anyone changes. tech-support does not route around the
    policy on the grounds that the account would technically allow it; the account allowing it is
    precisely the hazard this policy exists to cover.
- This composes with everything below: the **$2/hr** tripwire, right-size, verified-not-redundant,
  spend reporting, verified-pull-before-stop. The rules below still bind whoever runs the workload;
  the launch/terminate *actions* in them are tech-support's alone.

## Lifecycle discipline (hard rules)

1. **Preflight before ANY launch** ("if there's a chance the pod won't fire with the setup, don't run
   it"): CUDA tensor op on GPU + disk space + RAM check + data-presence gates + a 2-minute
   exact-command smoke INCLUDING the scoring step. Progress-based monitors, not time-based.
   **The launch itself is tech-support's action** (see the centralization rule above); a lane
   preflights and smokes, then files the bundle.
2. **Verified pull before stop/terminate.** These pods have no volume: stop or terminate WIPES the
   container disk. A restart also changes the SSH port. "Pull before stop" is upgraded to **verified
   pull before stop**: md5 (or sha) the pulled artifact against the remote **BEFORE** you stop —
   after the wipe the source is gone and you can never compare, so a silently-truncated pull becomes
   permanent, undetectable data loss. No exceptions. (seed4 incident: builder 138b151b, ratified
   eb19c9f5.)
   - **Pull-before-stop covers the artifacts the NEXT pre-registered step needs, not only the
     current read's inputs.** A "verified pull" that grabs the current step's numbers and tears
     down, leaving a downstream step's inputs on the wiped disk, is still a miss. Before you declare
     verified-pull and request teardown, look one step ahead in the pre-registered plan and pull what
     *it* consumes too. (Velox race, 2026-07-18: the admissibility read pulled only ADP logs and
     terminated; step (ii)'s budget-rescore needed per-node score vectors that died with the pod —
     recoverable only because determinism was measured, so a re-run reproduces them bit-exact. Owned
     builder 15396ada, ruled researcher 631910f5.) This binds the WORKLOAD lane; the teardown action
     stays tech-support's, fired on the lane's verified-pull signal.
3. **Pods off when idle.** Anything RUNNING bills every hour (3090 ≈ $0.46/hr). After any long
   operation, query the API and confirm zero pods remain.
3b. **Right-size the instance — match the box to the BOTTLENECK, not the pipeline.** A data
   rebuild / restore / parse / batching job is CPU+RAM-bound and uses ZERO GPU. Run it on a
   memory-optimized or CPU box, NOT a GPU box. The GPUs are the most expensive part of the bill and
   they sit at 0% the whole time. **2026-07-18:** an E5 corpus rebuild ran on 8× A100 SXM / 2TB at
   **$11.92/hr = $286/day** with **7 of 8 GPUs at 0%** — the real work was one Python process on ~55
   CPU cores + ~1 TB RAM. That is ~$12/hr for GPUs doing nothing. **Rule:** within the first few
   minutes of any run, `nvidia-smi`; if the GPUs are idle and the work is CPU/RAM-bound, you are on
   the wrong instance — move to a high-RAM CPU box. Spin a GPU box only when GPU training actually
   starts, and if a pipeline is rebuild-then-train, do the rebuild on the cheap box and only switch
   to the GPU box for the train stage. **HARD CEILING: aggregate burn over $2/hr is a tripwire, not
   a budget** — a job above it is wrong (right-size it) and gets redone, not paid for. tech-support's
   burn-watch catches a breach within ~2 minutes; on breach, right-size or kill immediately.
4. **Secure cloud for long runs.** Community pods are lemon-prone: dead GPUs mid-run (NVML unknown
   error), broken CUDA container mappings, pods with no TCP port at all.
5. **Verify uploads with checksums** before deleting local copies; verify pulls too — a 2-minute scp
   timeout can truncate an npz silently (BadZipFile later). Checksum after pull. **One file per scp
   call, or tar-pipe.** macOS `scp` in SFTP mode does NOT word-split a multi-file remote argument —
   `scp host:'a b c' dest/` fails **SILENTLY** (no error, exit 0, no files transferred). Copy one
   file per call, or stream several with a tar-pipe: `ssh host 'tar cf - a b c' | tar xf -`. (seed4
   incident: builder 138b151b, ratified eb19c9f5.)
6. **Disk fills kill chains silently:** a full /workspace makes scp fail and short-circuits `&&` chains
   (downstream files never created). Check `df -h /workspace` in preflight and before adding data;
   DARPA raw json is huge — delete consumed raw archives after corpus build.

## Monitoring discipline — NON-NEGOTIABLE

A running pod is a live obligation, not a fire-and-forget. It bills every hour whether or not it
is doing work, and a pod left running unwatched is money burning with nobody looking. These are
hard rules; a lane that runs a pod follows all of them.

**Register the pod on the bus, so nobody can abandon it silently.**
- The instant you launch a pod, `~/channels/bin/ch pod-up <you> <podId> "<what it's running>"`. The
  instant it stops/terminates, `ch pod-down <you> <podId>`. `ch pods` is the shared-account view —
  who has a pod up right now — and it is the check the rest of this discipline demands (below).
- `ch board` flags **🔥 ABANDONED POD** when a lane has a registered pod up and has been silent
  past `CHANNELS_POD_STALE_MIN` (default 90m — a multi-hour GPU run is legitimately quiet 1-2h per
  pass, so the heartbeat only needs to beat 90m). That flag outranks every other board state; if it
  is you, go check the pod or `ch pod-down` it before anything else.

**A running pod must have a live, progress-based monitor.**
- Arm a **persistent** monitor (Monitor tool) the moment the job starts; record its task id in your
  HANDOFF. No pod runs unwatched.
- The monitor filter **must emit on FAILURE states** (DIED / ABORTED / OOM / GPU-lost / NVML / SSH-fail),
  not only on DONE. A filter that fires only on success tells you nothing when it matters, and a dead
  monitor's silence is identical to a healthy one's. Prove the alarm can fire before you trust it.
- **Kill the monitor the instant the pod dies** (TaskStop). Monitor loops survive context compaction
  invisibly and will poll a terminated pod forever.

**Idle is waste — stop the instant work ends.**
- Stop the pod the moment the job finishes or the lane goes idle. Do analysis and writeup with **zero
  pods running**. After any long op, query the API and **confirm zero pods remain** (`ch pods` should
  be empty AND the RunPod API should agree — "I think I stopped it" is not confirmation).
- Provision freely but never redundantly: `ch pods` + check the RunPod account for a peer's pod first,
  confirm the artifact isn't already on disk or computable at $0, announce on the bus when you spin one
  up. (Standing operator directive: pods are free-rein, gated only on verified-not-redundant.)

**Wedged vs slow — the miscall that keeps happening.**
- Before calling a run "wedged"/"hung" and killing it, **sample CPU-TIME twice, seconds apart** (the
  process's accumulated CPU seconds — NOT %CPU, NOT output-file mtime). **Advancing CPU-time =
  compute-bound and PROGRESSING, full stop** — no matter how stale the log or how clean the last output
  row looks. Only *flat* CPU-time across two samples, plus no GPU util and no child-process progress,
  justifies "wedged." 100% CPU is evidence of compute, not of a hang. (This exact miscall — "output
  frozen 16 min, must be wedged" on a process whose CPU-time was advancing — has happened on the bus.)
- **Never terminate a pod on an ambiguous signal.** A pessimistic miscall that kills a healthy
  multi-hour run costs more than waiting one more sample.

**A pod that looks dead often isn't.**
- Wrong SSH key gives `Permission denied (publickey)`, IDENTICAL to a dead/reclaimed pod. Before
  declaring a pod dead, retry with the runpodctl key explicitly
  (`ssh -i ~/.runpod/ssh/runpodctl-ssh-key -o IdentitiesOnly=yes ...`). Never terminate on a single
  Permission-denied. (2026-07-12: this misdiagnosis terminated a healthy pod with unrecovered results.)

**Never lose the results, report signal not churn.**
- **Pull artifacts BEFORE any stop/terminate** — no volume, so stop/terminate WIPES the disk and a
  restart changes the SSH port. Checksum every pull; a truncated scp fails silently later.
- Monitor-driven bus updates are for progress that changes a decision or a failure that needs action,
  not a heartbeat every poll. Report results, not activity.

## Known env recipes

- **MAGIC (USENIX'24) stack:** micromamba env, python 3.10, `torch==1.12.1+cu116`, `dgl==1.0.0`
  (cu116 wheel index), `cudatoolkit=11.6` (provides libcusparse.so.11), `numpy<2`.
  Use `micromamba run -n <env>` for nohup (activation hooks fail in non-interactive shells).
  No `/usr/bin/time` in slim containers — time with shell `date`.
