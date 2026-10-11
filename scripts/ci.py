#!/usr/bin/env python3
"""Validate one module's maintenance contract; optionally run registered checks."""
import argparse
import fnmatch
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import subprocess
import sys

AGENT_FIELDS = {"identity", "responsibilities", "write_scope", "inputs_outputs",
                "tool_identity", "permissions", "budget", "acceptor", "handoff_location", "stop_method"}
STAGES = ["Plan", "Code", "Build", "Test", "Release", "Deploy", "Operate", "Monitor"]
PERMISSIONS = {"source_maintenance", "version_release", "production_deployment", "onchain_control"}
DEPENDENCY_KINDS = {"compile", "runtime", "behavior", "authority", "funds", "state", "content"}
EXPECTED = {"SDK": "soul-sdk", "DEVOPS": "ecosystem-devops", "INTEGRATION": "ecosystem-integration",
            "STANDARD": "soul-standard", "CONTENT": "soul-content", "COMMUNITY": "soul-community",
            "MAKER": "maker-protocol", "CHANNEL": "soul-channel", "MARKET": "soul-market",
            "EXTENSIONS": "soul-extensions"}
CONSUMER_FIELDS = {"provider_and_exact_interface", "used_actions_and_types", "supported_schema_and_behavior",
    "required_effects", "authority_and_state_inputs", "failure_exit_and_recovery",
    "version_combination_and_artifacts", "verification_and_migration_evidence"}
DEPENDENCY_FIELDS = {"consumer", "provider", "kind", "used_actions_types_state", "selection_condition",
    "exact_version_range", "change_validation", "exit_or_migration"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_relative(value, allow_pattern=False):
    require(isinstance(value, str) and bool(value), "path must be a nonempty string")
    path = PurePosixPath(value)
    require(not path.is_absolute() and not PureWindowsPath(value).drive and
            ".." not in path.parts and "\\" not in value,
            f"path escapes repository boundary: {value}")
    require(path.parts and path.parts[0] != ".git", "Git internals are outside declared write scope")
    if not allow_pattern:
        require(not any(c in value for c in "*?[]"), f"artifact path must be exact: {value}")
    return path


def validate_assignment(assignment, label):
    require(assignment["status"] in {"pending", "confirmed"}, f"invalid {label} mapping status")
    if assignment["status"] == "pending":
        require(assignment["actual_identity"] is None, f"pending {label} must not impersonate an actual identity")
    else:
        require(isinstance(assignment["actual_identity"], str) and assignment["actual_identity"].strip(),
                f"confirmed {label} needs an actual identity")
        require(assignment["evidence"], f"confirmed {label} requires identity assignment evidence")


def matches_path(path, pattern):
    # A recursive directory declaration also protects the directory itself.
    return fnmatch.fnmatchcase(path, pattern) or (pattern.endswith("/**") and path == pattern[:-3])


def validate_write_paths(root, config, changed_paths):
    boundary = config["write_boundary"]
    scope = config["agent_contract"]["write_scope"]
    require(boundary["writable_paths"], "write boundary must declare allowed repository paths")
    require(boundary["writable_paths"] == scope["paths"], "Agent and module write scopes differ")
    allowed = [str(safe_relative(p, allow_pattern=True)) for p in boundary["writable_paths"]]
    denied = [str(safe_relative(p, allow_pattern=True)) for p in
              boundary.get("non_writable_paths", []) + scope.get("read_only_dependency_paths", [])]
    repository_root = root.resolve()
    for changed in changed_paths:
        relative = str(safe_relative(changed))
        resolved = (repository_root / relative).resolve()
        require(resolved.is_relative_to(repository_root), f"changed path escapes repository boundary: {changed}")
        # Check both the declared path and its target, so local aliases cannot
        # turn a read-only dependency or an out-of-scope file into writable source.
        target = str(safe_relative(resolved.relative_to(repository_root).as_posix()))
        for path in {relative, target}:
            require(not any(matches_path(path, p) for p in denied),
                    f"changed path is read-only: {changed}")
            require(any(matches_path(path, p) for p in allowed),
                    f"changed path is outside module write scope: {changed}")


def validate_structure(root, config, changed_paths):
    module = config["module_id"]
    require(EXPECTED.get(module) == config["repository"], "module/repository identity differs from approved mapping")
    for name in ["README.md", "MODULE.md", "AGENTS.md", "COMPATIBILITY.md", "RUNBOOK.md",
                 "scripts/ci.py", ".github/workflows/ci.yml"]:
        require((root / name).is_file(), f"missing deliverable: {name}")
    require(set(config["agent_contract"]) == AGENT_FIELDS, "Agent contract must contain the ten original fields")
    require(config["agent_contract"]["identity"]["module"] == module, "Agent identity module differs")
    require(config["agent_contract"]["write_scope"]["repository"] == config["repository"], "Agent write scope differs")
    require(config["agent_contract"]["write_scope"]["cross_repository"] == "forbidden", "cross-repository writes must be forbidden")
    boundary = config["write_boundary"]
    require(boundary["repository_only"] is True and boundary["cross_repository_edits"] == "forbidden",
            "write authority must be limited to this repository")
    validate_write_paths(root, config, changed_paths)
    for path in root.rglob("*"):
        if path.is_symlink():
            require(path.resolve().is_relative_to(root.resolve()), f"symlink escapes repository: {path.relative_to(root)}")
    capabilities = config["engineering_capabilities"]
    require(capabilities["management_role_grants_runtime_authority"] is False,
            "management roles cannot grant runtime authority")
    require(capabilities["upgrade_authority_grants_runtime_authority"] is False,
            "upgrade authority cannot stand in for runtime authority")
    management = config["management"]
    require(set(management["functions"]) == {"planning", "organizing", "leading", "controlling"},
            "management functions must remain separate from tool capabilities")
    require(management["no_competing_board"] is True and management["preserve_active_owners"] is True,
            "existing task/owner authority must be retained")
    assignments = management["responsibility_mappings"]
    require(set(assignments) == {"maintenance", "independent_acceptance"}, "two responsibility mappings are required")
    for label, assignment in assignments.items():
        validate_assignment(assignment, label)
    if all(a["status"] == "confirmed" for a in assignments.values()):
        require(assignments["maintenance"]["actual_identity"] != assignments["independent_acceptance"]["actual_identity"],
                "independent acceptance must differ from implementation identity")
    require(config["agent_contract"]["acceptor"] == assignments["independent_acceptance"], "Agent acceptor mapping drift")
    require(config["agent_contract"]["identity"]["actual_identity"] == assignments["maintenance"]["actual_identity"],
            "Agent identity and maintenance mapping drift")
    require(config["agent_contract"]["identity"]["status"] == assignments["maintenance"]["status"],
            "Agent identity status and maintenance mapping drift")
    registry = management["original_record_registry"]
    require(set(registry) == {"Delivery", "DEV", "BUG"}, "must reference original Delivery/DEV/BUG registries")
    known = set()
    for label, entry in registry.items():
        require(entry["list_id"] and entry["url"] and entry["records"], f"missing original {label} registry")
        for record in entry["records"]:
            require(set(record) == {"id", "record_id", "url"} and all(record.values()), "original record reference fields invalid")
            known.add(record["url"])
    for record in management["original_scope_references"]:
        require(record["record_id"] and record["owner_ref"] and record["reviewer_ref"], "original scope owner/reference lost")
        known.add(f"{record['original_list_url']}?record_id={record['record_id']}")
    for ref in [management["current_record_ref"], config["delivery_attachment"]["original_record_ref"],
                config["release_readiness"]["original_record_ref"]]:
        require(ref is None or ref in known, "current attachment must target an original record URL")
    permissions = config["engineering_permissions"]
    require(len(permissions) == 4 and {p["category"] for p in permissions} == PERMISSIONS,
            "four separate engineering authority categories are required")
    for permission in permissions:
        require(permission["applicability"] in {"pending", "applicable", "not_applicable"}, "invalid permission applicability")
        if permission["applicability"] == "not_applicable":
            require(permission["reason"], "N/A permission needs a reason")
        elif permission["applicability"] == "applicable":
            require(permission["actual_holder"] and permission["authorization_ref"] and permission["evidence"],
                    "applicable permission must cite actual holder, authorization and evidence")
    delivery = config["delivery_attachment"]
    require(delivery["stage"] is None or delivery["stage"] in STAGES, "invalid delivery stage")
    require(delivery["status"] in {"pending", "in_progress", "blocked", "awaiting_acceptance", "complete"}, "invalid delivery status")
    require([s["stage"] for s in delivery["stage_exit_criteria"]] == STAGES, "all eight stage exit records are required")
    for stage in delivery["stage_exit_criteria"]:
        require(stage["exit_criteria"] and isinstance(stage["evidence"], list), "stage evidence and exit criteria must be separate")
        require(stage["status"] in {"not_verified", "passed", "failed", "not_applicable"}, "invalid stage evidence status")
        if stage["status"] in {"passed", "not_applicable"}:
            require(stage["evidence"], "passed or N/A stage requires evidence or N/A rationale attachment")
    compatibility = config["compatibility"]
    require(set(compatibility["consumer_declaration_fields"]) == CONSUMER_FIELDS, "consumer must retain eight original fields")
    require(set(compatibility["dependency_fields"]) == DEPENDENCY_FIELDS, "dependency must retain eight original fields")
    require(set(compatibility["dependency_kinds"]) == DEPENDENCY_KINDS, "seven dependency kinds are required")
    for consumer in compatibility["consumers"]:
        require(set(consumer) == CONSUMER_FIELDS, "each consumer needs all eight fields")
        require(all(v is not None for v in consumer.values()), "consumer fields cannot be undisclosed null")
    for dependency in compatibility["dependencies"]:
        require(set(dependency) == DEPENDENCY_FIELDS and dependency["kind"] in DEPENDENCY_KINDS, "invalid dependency record")
        require(dependency["consumer"] == module, "dependency consumer must be this module")
        require(dependency["provider"] != module, "self dependency must be handled as a release unit, not a cross-module edge")
        version = dependency["exact_version_range"]
        require(isinstance(version, str) and version.strip() and "latest" not in version.lower() and version != "*",
                "declared dependency must freeze a supported version range")
    require(set(compatibility["required_combinations"]) == {"baseline/current", "candidate/current", "candidate/candidate"},
            "three required compatibility combinations are required")
    require(compatibility["consumer_freeze_fields"] == ["source", "dependency_lock", "configuration", "artifact"],
            "unrelated consumers must freeze all four identities")
    for unit in config["release_units"]:
        require(all(unit.get(f) for f in ["id", "kind", "exact_version", "source_identity", "artifact_identity", "upgrade_boundary"]),
                "release unit needs exact source/artifact identity and actual upgrade boundary")
        require("latest" not in unit["exact_version"].lower(), "release unit cannot use floating latest")
    expected_pipeline = "cross_repository_integration" if module == "INTEGRATION" else "version_release"
    require([p["kind"] for p in config["pipelines"]] == ["ci", expected_pipeline], "logical pipeline count/ownership drift")
    for key, provenance in config["source_provenance"].items():
        safe_relative(provenance["path"])
        require(len(provenance["sha256"]) == 64 and all(c in "0123456789abcdef" for c in provenance["sha256"]),
                f"invalid source provenance digest: {key}")


def validate_evidence(root, items, label):
    require(isinstance(items, list) and items, f"missing {label}")
    for item in items:
        require(isinstance(item, dict) and {"path", "sha256"}.issubset(item), f"{label} needs path and sha256")
        path = root / str(safe_relative(item["path"]))
        require(path.resolve().is_relative_to(root.resolve()) and path.is_file(), f"{label} path missing/outside repository")
        require(hashlib.sha256(path.read_bytes()).hexdigest() == item["sha256"], f"{label} hash mismatch: {item['path']}")


def validate_release(root, config):
    ready = config["release_readiness"]
    require(ready["status"] == "ready", "release readiness is pending; scaffold CI is not product acceptance")
    require(ready["candidate_identity"] and ready["original_record_ref"] and ready["authorization_ref"],
            "release requires exact candidate, original task and existing execution authorization")
    assignments = config["management"]["responsibility_mappings"]
    require(all(a["status"] == "confirmed" for a in assignments.values()), "actual maintenance and independent acceptance mappings are pending")
    require(assignments["independent_acceptance"]["qualification_evidence"] and
            assignments["independent_acceptance"]["independence_evidence"], "acceptance requires actual qualification and independence evidence")
    require(config["release_units"] or config["module_id"] == "INTEGRATION", "actual independent release units are pending")
    for label in ["build_evidence", "test_evidence", "combination_evidence", "independent_acceptance_evidence", "recovery_evidence"]:
        validate_evidence(root, ready[label], label)
    require(config["ci"]["product_verification"] == "passed", "registered product checks must have run and passed for candidate")
    require(config["ci"]["product_commands"], "release requires actual registered product validation commands")
    print("Readiness materials checked; this does not grant final approval or execute publication/deployment.")


def run_product(root, config):
    commands = config["ci"]["product_commands"]
    require(commands, "no product commands registered; maintenance contract validation is not a product build/test")
    for command in commands:
        argv = command["argv"]
        require(isinstance(argv, list) and argv and all(isinstance(v, str) and v for v in argv), "command argv must be a nonempty string array")
        require(command["id"], "registered product command needs an id")
        timeout = command.get("timeout_seconds", 300)
        require(isinstance(timeout, int) and 1 <= timeout <= 3600, "product command timeout must be bounded")
        for arg in argv:
            require(".." not in PurePosixPath(arg).parts and not PurePosixPath(arg).is_absolute(),
                    "product command cannot declare an external filesystem path")
        result = subprocess.run(argv, cwd=root, timeout=timeout, text=True, capture_output=True, check=False)
        print(json.dumps({"command_id": command["id"], "argv": argv, "returncode": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr}, ensure_ascii=False))
        require(result.returncode == 0, f"product check failed: {command['id']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--changed-path", action="append", default=[])
    parser.add_argument("--product", action="store_true")
    parser.add_argument("--release-ready", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    config = json.loads((root / "module.json").read_text(encoding="utf-8"))
    validate_structure(root, config, args.changed_path)
    if args.product:
        run_product(root, config)
    if args.release_ready:
        validate_release(root, config)
    print(json.dumps({"module": config["module_id"], "maintenance_contract": "passed",
        "product_checks": "passed" if args.product else "not_run_by_this_command",
        "release_materials": "checked" if args.release_ready else "not_checked",
        "remote_execution_or_deployment_verified": False}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (KeyError, TypeError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(f"module check failed: {error}", file=sys.stderr)
        sys.exit(1)
