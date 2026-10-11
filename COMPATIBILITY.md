# Consumed contracts and verification combinations

Register actual consumers and dependencies in module.json.compatibility. An empty list means Gate0 is incomplete; it does not establish zero dependencies.
Configuration declares, and CI validates, eight fields per consumer, eight per dependency, and seven dependency categories.
Record the provider's exact interface, actual actions/types, schema/behavior, required effects, permissions/state, failure/exit/recovery, version/artifacts, and verification/migration evidence separately.

Review changes across four dimensions: types/formats/ABI, behavior, permissions/funds, and migration/old entry points.
Verify at least baseline/current, candidate/current, and candidate/candidate; add reverse combinations when consumption is bidirectional.
Pin source, dependency locks, configuration, and artifacts; reject floating latest and incorrect hashes. Reverification does not automatically require unrelated consumers to republish.
For unknown passive extensions, the target is 0 forced Market releases. Perform or explicitly reject funds/authorization/supply/transfer/content/exit obligations according to the contracts actually selected.

Register each actual package/SDK artifact, type origin, exact dependencies, and upgrade boundary in release_units. Disclose shared upgrade boundaries for shared UpgradeCaps.
Version numbers, directory splits, and compilable ABIs do not prove compatibility for funds, authorization, or recovery.
