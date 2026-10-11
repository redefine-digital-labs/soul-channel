# Operation, failure, and recovery

1. Pin the candidate's source/diff, dependency locks, configuration/artifact digests, environment/network, relevant packages/objects, and consumers in the original record.
2. Run this repository's CI and registered product commands; retain logs and summaries. Unregistered, unperformed, or failed gates must not be rewritten as passed.
3. An actual independent acceptor checks the exact combination and recovery. release-ready checks material completeness; final approval still follows original authorization.
4. Authorized executors perform production deployment, upgrades, initialization, and signing at the exact target and read back the result. This template does not automatically perform these operations.
5. For failures, record the original intent/digest, effects, paid resources, and checkpoints. Query the original result first when the outcome is unknown. A readback failure after success does not make the result unknown; do not repeat minting/upload/payment.
6. Frontends/SDKs can revert to pinned artifacts; do not assume on-chain state, transfers, or upgrades are reversible. Verify the actual actions covered by pause/resume and lawful exits individually.
7. Attach the handoff to the original record, retaining source candidates/evidence/remaining conditions. Release exclusive resources such as wallets, browsers, and deployment environments. Stopping an executor does not delete historical assets or paid resources.

Operational responsibilities, monitoring sources/windows/thresholds, recovery drills, and actual production targets remain pending until established. Without actual observations, do not claim monitoring is enabled.
Tooling repositories do not own business operational gates. Handle cross-repository failures for the exact affected combination and hand off to the relevant maintainer.
