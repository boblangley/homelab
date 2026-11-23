# Homelab update inventory

Use this inventory to track what needs upkeep. As each routine is ready, link it from its entry. A routine should say when to run it, what to do, and how to verify the result.

The initial inventory comes from the Ansible configuration and read-only checks on the seven managed hosts on 2026-11-23. The [host inventory](../inventory/hosts.yml), [playbook](../site.yml), and role defaults track Ansible assignments and version pins.

## Hosts, firmware, and network

| Target | What to keep current | Routine |
| --- | --- | --- |
| Managed Linux hosts | Ubuntu 26.04 LTS on `docker-infra`, `wtr-pro`, `ser6-p`, `ser6-max`, `m1-1295`, and `gtr6`. Debian 13 on the ARM64 `rp4`. Track security and package updates, kernels, release upgrades, bootloaders, installed snaps, and the QEMU guest agent on `docker-infra`. | |
| Physical hosts | BIOS/UEFI, CPU microcode, device firmware, and SSD/NVMe firmware for the five x86 workers and the Proxmox host. Track Raspberry Pi EEPROM and board firmware on `rp4`, and the bootloader and board firmware on `r5s`. | |
| Docker fleet | Docker Engine, CLI, containerd, Compose, Buildx, and installed rootless extras. `docker-infra` is the sole Swarm manager. See the [Docker package list](../roles/docker/defaults/main.yml). | [Check Docker versions](update-routines/check-docker-versions.md) |
| Proxmox VE on `v4670` | Host OS and kernel, hypervisor and storage packages, guest tools, guest operating systems, and backup tooling. `docker-infra` is a KVM guest. Verify the full guest inventory. | |
| OPNsense at `gateway.internal` | Firewall base system, installed plugins, and Unbound. The ingress manager uses the OPNsense API to maintain DNS overrides and port forwards. | |
| OpenBao on `r5s` | OpenBao server, `bao` clients, and the `r5s` OS and packages. OpenBao serves secrets, PKI, and SSH signing for the homelab. See the [OpenBao deployment](external.md#openbao). | |

## Services and workloads

| Where | What to keep current |
| --- | --- |
| Docker fleet | Wyrwood controller and host agents, Arcane manager and worker agents, OpenTelemetry gateway and host collectors, and the workers' Docker socket proxies. Each of the three controller or gateway stacks shares [a version pin](../group_vars/all.yml) with its agents. |
| `docker-infra` | Homelab Ingress Manager and its bundled Caddy and plugins, Go dependencies and base images, CoreDNS, Pi-hole and its blocklists, the Tailscale subnet router, Cloudflare Tunnel (`cloudflared`), Pocket ID, Xolotl, and the self-hosted GitHub Actions runner. Xolotl's [Codex client version for model discovery](../roles/wyrd/templates/config.toml.j2) is a separate pin. |
| `wtr-pro` | NATS and JetStream, `nats-box` and `nsc` for stream management and credential provisioning, ClickHouse and its schemas and backup tooling, Grafana and the ClickHouse datasource plugin, ntfy and its curl sidecar, Trowel, and Deck. The [ntfy provisioning script](../scripts/openbao/ntfy-users.fish) also pins the ntfy image. |
| `ser6-max` | PostgreSQL 18 and pgvector. Arcane runs Hermes with the `latest` tag. An OtterWiki project definition uses tag `2` and had no container at inventory time. |
| `m1-1295` | Arcane runs Dashy with the `latest` tag. |
| `gtr6` | Menagerie server, its [job runner image](../roles/menagerie/defaults/main.yml), the [registered Workspace template](external.md#wyrwood), and the host's `dcb` and `toha` packages. The 11 running devcontainers have their own base images, Features, toolchains, and packages. Track T3 Code Server, Dagu, coding-agent CLIs, language runtimes, package managers, workspace Ansible, dotfiles, skills, and shared workflows where installed. |

## Deployment, access, and recovery

- **Deployment tooling.** The Ansible playbooks, workstation Ansible environment, `ansible-core`, Galaxy collections, Python `hvac`, the GitHub Actions runner base image and OS packages, `actions/checkout`, and `gh-vault-agent-app-token`. The [Apply workflow](../.github/workflows/apply.yml) skips the [runner](../roles/runner/files/Dockerfile) itself.
- **Certificates, keys, and client tools.** Homelab root and intermediate CAs, Caddy ACME certificates, [Ansible-issued service TLS certificates](../roles/service_cert/defaults/main.yml), SSH user certificates and trust stores, package signing keys, and credentials with expiry or rotation requirements. Include operator tools such as Tailscale, `bao`, Deck, and `ssh-cert-refresh`.
- **External integrations.** Cloudflare routes and DNS, GitHub Apps and webhooks, Pocket ID OIDC clients, Wyrwood bindings, and the Deck Discord bot integration. See [configuration outside Ansible](external.md).
- **Backups and recovery.** ClickHouse archive and backup jobs, Backblaze B2 credentials and lifecycle rules, and the applicable backup tooling and restore procedures for OpenBao, Proxmox guests, stateful services, and workspaces. The [B2 backup configuration](external.md#backblaze-b2) covers ClickHouse.

## Inventory gaps

- Confirm the Proxmox release and guest list, the OPNsense release and installed plugins, and the `r5s` OS and firmware.
- Identify any switches, Wi-Fi access points, modem or ONT, NAS, UPS, or other appliances that belong in the plan.
