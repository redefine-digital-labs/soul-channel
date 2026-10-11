# CHANNEL execution boundaries

- Read MODULE.md, COMPATIBILITY.md, RUNBOOK.md, and module.json, then the original record and exact candidate; historical status is reference only.
- The original Owner and original record are the responsibility entry points. The recommended role CIPHER is not an actual account; unconfirmed maintenance/acceptance mappings remain pending.
- Write this module only in this repository's authoritative worktree. Do not modify other repositories through relative paths, symlinks, integration fixes, or tooling scripts. Hand cross-repository issues to the maintainer identified by the original record.
- Each semantic unit has only one writer at a time. Parallel work requires scoped authorization, capacity within the original WIP limit, isolated write scopes, pinned inputs, independent review capacity, and no shared-resource conflicts.
- Maintenance/upgrade roles do not confer wallet, asset, operational, or deployment permissions. Follow original explicit authorization; documentation creates no new signing, spending, or external communication permission.
- The 10 contract fields are in module.json.agent_contract: identity, responsibilities, write_scope, inputs_outputs, tool_identity, permissions, budget, acceptor, handoff_location, stop_method.
- Attach stage, status, evidence, exit criteria, and handbook applicability to the original Delivery/DEV/BUG records. Do not create another task board; preserve original milestones and active Owners.
- High-risk work requires review by a qualified, actual independent acceptor. Role labels and executor self-review cannot stand in for independent approval.
- Unperformed build/test checks remain not_run. Template CI success does not establish business acceptance, independent release, deployment, or external audit.

Dependency snapshots `.deps/` and `candidate-dependencies/` are read-only build inputs, never a second business source authority. Changes require an explicit new candidate and dependency pin; do not edit another repository through an old-path link.
