# Cloud session: the standing prompt (copy of the scheduled task, for reference)

The scheduled task "Stickspire cloud queue (twice daily)" runs at 08:52 and 20:52 London in a
fresh cloud session with this prompt. It takes only the CLOUD queue in `docs/NEXT-SESSION.md`
(tasks whose board "Where" column says Cloud), works one task per branch
`cloud/<board-number>-<slug>`, may run one subagent per lane in parallel on separate branches,
and uses a separate QA subagent as the only one allowed to tick a task after the sabotage
pass. Headless proofs go to `proof/<date>-<task>/`; visual ones are marked UNVERIFIED ON
SCREEN and a "capture proof for <task>" line is added to the PC queue. After each merge it
appends a row to the Build log tab. It never takes PC items, never decides Open decisions,
never buys anything, never touches the Unreal repo. Edit the real prompt in the scheduled
task, then mirror the change here.
