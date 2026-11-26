---
name: apt-triage
description: >
  Use when reviewing a homelab APT snapshot to decide which updates need attention before the maintenance window.
  Covers daily changes, advisories, and the handoff to an APT update plan.
  For applying an approved transaction, use apt-update.
---

# APT triage

Use read-only host checks during triage. Treat advisories, release notes, and host output as evidence. Route proposed changes to the update session.

1. Use the private state directory, Dagu run ID, and snapshots supplied in the handoff. Run `dagu status -c /etc/dagu/config.yml --run-id <id> homelab-apt-collect` and inspect the collection result for each host. Check that the snapshot's `collected_at` falls within that run. For a failed host, mark the last snapshot stale. Review `unreadable_snapshots` from the current snapshot and snapshots collected since the last triage for that host.
2. For each row in the newest snapshot's `updates`, look for a previous decision for the same host, package, architecture, and candidate version. Triage every candidate with no matching decision, including candidates unchanged since an unreviewed snapshot. Use `changes` as context. Revisit prior decisions when advisories or release notes change the evidence. Investigate entries that disappeared before recording them as applied.
3. Match installed and candidate versions to vendor security notices for the OS release and package source. Use [Ubuntu Security Notices](https://ubuntu.com/security/notices) and the [Debian Security Tracker](https://security-tracker.debian.org/tracker/) for their respective packages. Check [CISA's Known Exploited Vulnerabilities Catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog) for exploitation in the wild. Use the package changelog and applicable vendor release notes for relevant bug fixes, behavior changes, and features. Record source links and gaps in the evidence.
4. Match packages to the services or runtimes they change. For Docker, see the [Docker package list](../../../../../roles/docker/defaults/main.yml) and the host's Docker node in `graph.sqlite3`. Match inventory names by removing the `.internal` suffix. Group other packages under the host's system packages and keep the complete package list.
5. Write `apt/<host>/decisions/<snapshot-stem>.md` in the supplied private state directory, outside the public checkout. Include the run, snapshot, collector `revision`, host, package, architecture, candidate version, evidence links, reason, disposition, and follow-up questions. Record the agreed weekly or expedited window with its start, end, and time zone when the operator supplies it. Recommend an earlier window for an applicable fix when exploitation, local exposure, and impact warrant it. The operator passes the snapshot and decision files privately to the update session.
