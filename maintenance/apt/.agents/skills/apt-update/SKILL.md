---
name: apt-update
description: >
  Use when planning, applying, or verifying a weekly or expedited homelab APT maintenance window.
  Covers the proposed package transaction, dependency impact, operator review, and verification.
  For evaluating newly available updates, use apt-triage.
---

# APT update

1. Read the private snapshot and decision file supplied by the operator. Confirm the targets, reason, window and time zone, SSH identity, and recovery access. Use the operator's private state directory for the session result.
2. Generate the proposal using current APT indexes. When the operator approves an index refresh for this window, refresh first and simulate afterward. For a normal upgrade that permits new dependencies, simulate `apt-get -s --with-new-pkgs --no-remove -V upgrade`. For a targeted update, simulate `apt-get -s --no-remove -V install <package>=<version>` with the selected versions.
3. Present every package APT proposes to upgrade, install, or remove, with current and proposed versions, and record deferrals. In `graph.sqlite3`, match an inventory host after removing `.internal`. Walk edges in reverse by looking for rows whose `dependency_id` matches the current node, then following their `dependent_id`. Use the host for the system packages rollup and the specific runtime or service for tracked packages. Use the Ansible role's health check and the operator's recovery access for the verification plan. Mark missing checks or graph edges as unknown.
4. Apply only to the hosts and transaction the operator authorized. Use an attached terminal and let the operator decide configuration-file prompts. Re-simulate immediately before applying and take material changes back to the operator. For the normal upgrade, use the command below and compare the displayed transaction with the approved plan at the prompt. For a targeted update, replace `--with-new-pkgs -V upgrade` with `-V install <package>=<version>` using the approved package versions. List-only `needrestart` leaves its service restarts to the operator. Package scripts can still restart services during the window.

   ```sh
   sudo env NEEDRESTART_MODE=l apt-get -o APT::Get::Assume-Yes=false --no-remove --with-new-pkgs -V upgrade
   ```

5. If interrupted, check for an active package-manager process and run `sudo dpkg --audit`. If unfinished configuration remains, review the recovery with the operator before running `sudo dpkg --configure -a`. Check reboot signals and `needrestart` where available. Verify installed and running versions and the affected services after authorized restarts.
6. Write `apt/<host>/updates/<window-id>.md` in the workstation's private state directory, outside the public checkout. Record the approved plan, actual package changes, deferred updates, restart and service checks, and work that remains pending. Keep the transaction and host observations with the private handoff.
