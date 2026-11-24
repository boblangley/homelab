---
name: apt-update
description: >
  Use when planning, applying, or verifying a weekly or expedited homelab APT maintenance window.
  Covers the proposed package transaction, dependency impact, operator review, and verification.
---

# APT update

1. Identify the hosts, maintenance window, and reason from the triage handoff. Confirm the SSH target and recovery access before planning an interruption.
2. Simulate the intended APT command on each target. For a normal upgrade that permits adding dependencies, use `sudo apt-get -s --with-new-pkgs upgrade` if that is the intended operation. For a targeted update, simulate the exact package and version selection.
3. Present every package APT would upgrade, install, or remove, with current and proposed versions, and record relevant deferrals. Link tracked packages to graph nodes and trace which services and capabilities may be interrupted. Include expected restarts, recovery access, and health checks.
4. Apply only the transaction and hosts the operator authorized. Recheck the simulation immediately before applying. Bring material changes to the plan back to the operator for review.
5. Record the actual transaction and deferred packages. Check reboot signals and `needrestart` where available. Verify running versions and the affected services after any authorized restart, and report work that remains pending.
