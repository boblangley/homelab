---
name: apt-triage
description: >
  Use when reviewing a homelab APT snapshot to decide which updates need attention before the maintenance window.
  Covers daily changes, advisories, and the handoff to an APT update plan.
---

# APT triage

1. Open the snapshot named in the handoff and check its host, collection time, and successful collector status. For an unreachable host or failed collection, report missing or stale data and use its last successful snapshot for context.
2. Review new and changed candidates in `changes`. The first successful snapshot presents every candidate for triage. Investigate entries that disappeared before recording them as applied. Carry unchanged pending candidates into the maintenance plan, and revisit any affected by new advisories or release notes.
3. Match installed and candidate versions to vendor security notices for the OS release and package source. Use [Ubuntu Security Notices](https://ubuntu.com/security/notices) and the [Debian Security Tracker](https://security-tracker.debian.org/tracker/) for their respective packages. Check [CISA's Known Exploited Vulnerabilities Catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog) for exploitation in the wild. Use the package changelog and applicable vendor release notes for relevant bug fixes, behavior changes, and features. Record source links and gaps in the evidence.
4. Match packages to the services or runtimes they change. For Docker, see the [Docker package list](../../../../../roles/docker/defaults/main.yml) and the host's Docker node in the dependency graph. Group other packages under system packages with the full package list available.
5. Record each decision with the host, candidate, reason, and disposition. Use the regular window for routine changes and flag an earlier window when applicability, exposure, and impact warrant it. Include unresolved questions and hand off the dated snapshot and decisions to the update session.
