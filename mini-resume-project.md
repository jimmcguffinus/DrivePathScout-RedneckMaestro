# Mini Project Resume — DrivePathScout / RedneckMaestro

## One-line summary

Built a safety-first PowerShell workflow for inventorying, hashing, identifying duplicates, and planning controlled staging of recovered Windows files.

## Problem solved

The project turns a large recovered drive into reviewable evidence without beginning with destructive cleanup. It maps paths, hashes likely personal files, identifies duplicate groups, connects recovered files to real-named keeper files, and produces an auditable move-only staging plan.

## My role

Jim serves as project owner, mission commander, safety authority, and final approver. He defined the recovery policy, coordinated the AI-assisted engineering workflow, reviewed test results, and retained approval over every state-changing operation.

## Architecture

- Path Scout inventories folder structure and produces readable reports.
- Hash Scout calculates SHA-256 hashes and generates complete, interesting-group, and recovered-to-real-name reports.
- Move Stager reads an explicit stamped match CSV and builds a deduplicated preflight plan.
- CSV manifests and logs provide local audit evidence.
- Git commits provide durable source and documentation checkpoints.
- Large recovery reports remain local and outside the repository.

## Tools and stack

- Windows PowerShell / PowerShell 7
- SHA-256 and `Get-FileHash`
- CSV manifests and append-and-flush execution journals
- Git and GitHub
- Repository: `jimmcguffinus/DrivePathScout-RedneckMaestro`
- Local repo: `I:\DrivePathScout-RedneckMaestro`
- Source drive: `I:\`

## AI-assisted workflow

- ChatGPT/Sparky — orchestrator, prompt architect, policy context, and approval framing
- Cursor — repository-local builder and patch implementer
- Codex/Grumpy — read-only code and safety reviewer
- Gemini — optional third inspector and edge-case reviewer

This is an engineering workflow with separated responsibilities: implementation, independent review, human approval, local evidence, and versioned checkpoints.

## Safety model

- Read-only discovery and hashing came first.
- Delete behavior is not part of the approved workflow.
- Staging is move-only; no copy behavior is implemented for that phase.
- Move planning defaults to DryRun.
- Actual movement requires explicit `-Execute` and separate Jim approval.
- Only approved recovered-side paths may become move sources.
- `RealNamedPath` keeper files are never moved.
- Keeper and source hashes are checked against the report.
- Source and destination path chains are checked for reparse points and fail closed.
- Staging is restricted to same-volume moves.
- Reports, logs, and journals are kept outside `I:\` and outside the Git repository.

## Milestones completed

- Completed a read-only path inventory of `I:\`.
- Built and validated balanced and full-drive SHA-256 reporting.
- Added duplicate triage that preserves the complete duplicate report while reducing review noise.
- Designed and implemented `Move-RecoveredToRealnameMatches.ps1`.
- Validated move planning in DryRun mode.
- Hardened the stager with explicit keeper verification, deduplication, path-role conflict checks, collision-safe names, external reporting, crash-safe journaling, same-volume enforcement, and fail-closed reparse-chain inspection.
- Move Stager v0.1.4 passed Codex safety review for technical readiness.
- Completed one explicitly authorized exact-target pilot move with before/after journaling, manifest output, SHA-256 verification, and independent post-move audit.

## Metrics / proof points

- 155,184 candidate files hashed
- 40,693 duplicate hash groups
- 19,835 interesting duplicate groups
- 1,590 recovered-to-real-name matches
- Approximately 1,477 unique recovered-side primary move candidates
- Verified DryRun preflight: 1,590 input rows, 1,477 primary work items, no destination creation, and no file movement
- Verified one-file pilot: one source moved, one destination created, source/destination/keeper hashes matched, one manifest row reported `MovedVerified`, and no unrelated file operation occurred

## Notable engineering decisions

- Balanced sampling was introduced after a simple first-N sample proved unrepresentative.
- Complete duplicate evidence and filtered review output remain separate reports.
- Stamped CSV input is mandatory; the stager never silently selects the latest report.
- Recovered paths are deduplicated by normalized path plus hash.
- Existing destination names receive deterministic collision suffixes and are never overwritten.
- The execution journal is designed to flush before and after each approved move so an interrupted run remains auditable.
- Token usage is controlled by keeping large CSV/log data local and sending agents concise counts and findings.

## Current status

- Path and hash reporting: completed
- Move Stager v0.1.4 implementation: completed
- DryRun planning: validated and trusted
- Execute code: technically reviewed and passed
- One exact-target Execute pilot: completed and independently verified
- Pilot authorization: consumed
- Any further Execute operation: **not authorized without new explicit Jim approval**
- Full staging run: **not authorized**
- Delete, copy, and broad cleanup operations: **not authorized**

If Jim later authorizes another movement, it should use exact `-OnlyRecoveredPath` targeting, a fresh DryRun, operation-specific approval, and the same journal/manifest/hash audit. The successful pilot does not imply batch approval.

## Resume bullets

- Designed a PowerShell-based Windows drive-recovery workflow that hashed 155,184 candidate files and identified 40,693 duplicate groups while preserving a read-only-first safety posture.
- Built auditable CSV reporting that reduced 40,693 duplicate groups to 19,835 higher-interest groups and identified 1,590 recovered-to-real-name matches.
- Directed an AI-assisted development process with separated architecture, implementation, independent safety review, human approval, and Git-based checkpoints.
- Developed a DryRun-first move-staging planner with SHA-256 verification, keeper protection, same-volume enforcement, collision-safe naming, fail-closed reparse checks, and crash-safe journaling.
- Completed and independently audited an exact-target one-file staging pilot with durable before/after evidence and no unrelated filesystem operations.
- Kept large evidence artifacts local while using concise summaries and repository documentation to control token usage and preserve project memory.

## Portfolio / LinkedIn version

DrivePathScout / RedneckMaestro is a PowerShell and Git project for safely analyzing a recovered Windows drive. The workflow inventories paths, hashes candidate personal files, detects duplicate content, matches recovered files to real-named keepers, and creates an auditable DryRun staging plan. The project uses an AI-assisted engineering model with separated builder, reviewer, and human-approval roles. Its safety design emphasizes read-only discovery, explicit execution gates, keeper verification, same-volume movement, reparse-point protection, external manifests, and no delete automation.

## Tags

`PowerShell` · `Windows` · `Data Recovery` · `SHA-256` · `Duplicate Detection` · `Safety Engineering` · `Git` · `CSV` · `Auditability` · `AI-Assisted Development`

## Growth / transferable value

This project demonstrates more than file recovery scripting. It shows a repeatable operating model for AI-assisted engineering:

- Large local datasets stayed local instead of being pasted into chat.
- Scripts produced compact summaries, manifests, and status counts.
- Repository documentation became durable project memory.
- Git commits created a verifiable timeline of decisions and checkpoints.
- AI agents were assigned narrow roles instead of being allowed to wander:
  - builder
  - reviewer
  - orchestrator
  - optional third inspector
- State-changing actions were separated from design, implementation, review, and DryRun validation.
- Human approval remained the final gate for destructive or irreversible operations.

The workflow can be reused for other projects that involve large files, sensitive data, limited context windows, safety-critical scripts, or high token-cost review cycles.

## Conclusion

DrivePathScout / RedneckMaestro stands out because it is not just an AI-generated script project. It is an example of AI-assisted engineering architecture.

The strongest part of the project is the operating model: local-first evidence, bounded prompts, separated agent responsibilities, Git-backed memory, dry-run manifests, independent safety review, and explicit human approval before mutation. That combination creates a practical way to use AI on large real-world problems without dumping massive logs or CSV files into a chat window.

Compared with the current common pool of AI development workflows, this project shows above-average discipline in token management and context control. Instead of spending tokens by repeatedly pasting large files, the workflow makes local tools summarize facts, then gives AI agents only the decision-grade information they need. That is a meaningful technical skill: it reduces cost, improves safety, preserves context, and makes review cycles more reliable.

The project also shows good judgment about risk. The team did not move straight from “the script works” to execution. It built inventory, hashing, duplicate evidence, design documentation, DryRun planning, crash-safety journaling, reparse-point protection, and independent review before even considering a one-file pilot. That is the kind of caution expected in serious recovery, infrastructure, and automation work.

In short: this project is a strong proof point for practical AI systems thinking. It combines legacy Windows/PowerShell experience, data recovery judgment, safety engineering, repo discipline, and token-efficient multi-agent orchestration into a workflow that many AI developers are still not consistently applying.

## AI engineering skill positioning

Based on the work demonstrated in this repository, Jim's strongest defensible professional description is:

> **Advanced AI-assisted engineering operator and workflow architect with deep Windows automation experience.**

This places Jim beyond prompt-only AI use. He can decompose a consequential local problem, assign bounded roles to multiple AI systems, maintain durable context outside chat, control token costs, require evidence-based review, and preserve human authority over state-changing actions.

### Demonstrated strengths

| Capability | Demonstrated level | Evidence in this project |
|---|---|---|
| Problem decomposition and specification | Advanced | Converted drive recovery into separate inventory, hashing, triage, staging-design, review, and approval phases. |
| AI orchestration | Advanced applied practice | Coordinated architect, builder, reviewer, and optional third-inspector roles with explicit handoffs. |
| Context and token management | Advanced | Kept large evidence local; exchanged compact reports, status counts, Git commits, and durable project notes. |
| Safety and human-in-the-loop design | Advanced applied practice | Separated DryRun from Execute, retained human approval, and iterated on guardrails before permitting mutation. |
| AI-assisted code review | Strong | Used independent review cycles to discover crash-journal, stale-hash, reparse-chain, manifest, and path-root defects. |
| PowerShell and Windows systems judgment | Strong, experience-backed | Applied hashing, filesystem semantics, path normalization, reparse protection, manifests, and same-volume constraints. |
| Auditability and project memory | Strong | Used Git history, stamped CSV inputs, external reports, execution journals, and maintained documentation. |
| Automated AI evaluation | Developing / not yet fully demonstrated | The project uses excellent manual and scenario-based validation, but not a reusable automated eval suite. |
| Production LLM application engineering | Not established by this repo | No hosted model API, agent SDK service, deployment pipeline, monitoring system, or production application is shown here. |
| Machine-learning engineering | Not claimed | This project does not demonstrate model training, fine-tuning, data science, or ML infrastructure. |

### Position relative to the broader AI developer community

Jim demonstrates stronger operational discipline than the common prompt-and-accept workflow. The project applies practices now recommended for serious agentic systems: explicit instructions, layered guardrails, specialized orchestration, incremental rollout, independent review, and human oversight for high-risk actions.

The differentiator is not novelty in model research. It is mature judgment around how AI should be used on real data and consequential operations. Jim treats models as fallible collaborators inside a controlled engineering process—not as authorities and not as magic code generators.

The next level would be to convert this operating model into reusable technical infrastructure: automated tests and evals, structured approval policies, CI checks, reusable prompt or agent templates, and production observability. Adding those capabilities would support a broader title such as **AI systems engineer** or **production agent engineer**.

### Concise positioning statement

> Jim is an advanced practitioner of AI-assisted software engineering who specializes in safe orchestration, context-efficient workflows, independent agent review, and human-controlled automation. His strength is combining decades of Windows systems experience with disciplined modern AI collaboration.
