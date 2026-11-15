# Outside Ansible

What the roles depend on that is configured by hand, in another system's own interface or with the scripts in
[`scripts/openbao/`](../scripts/openbao). Names only; values live where they're stored. Keep this current with the
change that alters it.

## OpenBao

`https://openbao.internal:8200`, on r5s. Two namespaces: the root namespace, and `wyrwood`, where Wyrwood and the
homelab's data live.

### Mounts

| Namespace | Mount | Holds |
| --- | --- | --- |
| root | `pki` | Homelab Root CA |
| root | `pki_int` | ACME intermediate (role `homelab`): Caddy's certificates |
| root | `ssh-user-ca` | SSH user certificates (`sign/user`), for `ssh-cert-refresh` on workstations |
| root | auth `oidc` | Sign-in with Pocket ID (`bao login -method=oidc`) |
| `wyrwood` | `kv` (v2) | Secrets and installation identifiers, below |
| `wyrwood` | `transit` | Signing keys that never leave OpenBao, such as `homelab-ansible` (the `ansible` account's SSH key) and `gh-app-homelab-runner` |
| `wyrwood` | `pki_services` | Homelab Services Intermediate CA, name-constrained to `.internal`. Role `homelab-services`: `*.internal`, EC P-256, 30 days, no IP SANs. Role `service_cert` issues from it |

### Policies

| Namespace | Policy | Grants |
| --- | --- | --- |
| root | `homelab-ansible` | Read `wyrwood/kv/data/homelab/*`; issue from `wyrwood/pki_services/issue/homelab-services`. Given to the operator's OIDC identity, for workstation runs |
| root | `ssh-user` | Sign SSH user certificates. Given with the OIDC login |
| `wyrwood` | `homelab-runner` | The Actions runner's binding; includes issuing from `pki_services/issue/homelab-services` |
| `wyrwood` | Wyrwood policy `homelab-agent` | Read `transit/keys/homelab-agent` and update `transit/sign/homelab-agent`; offers the `homelab-agent` SSH identity. Selected only by `devcontainer-boblangley-dev` on gtr6 |

Policies in `wyrwood` that Wyrwood bindings use are edited in Wyrwood's interface, not with `bao policy write`.

### `kv` paths (namespace `wyrwood`)

| Path | Fields | Read by |
| --- | --- | --- |
| `homelab/accounts` | the people on each host | `accounts` |
| `homelab/arcane` | `encryption_key` | `arcane` |
| `homelab/b2/clickhouse` | `key_id`, `application_key` | `clickhouse` (archive and backups) |
| `homelab/clickhouse/<user>` | `password` | `clickhouse`, `otel_gateway` (`otel`), `grafana` (`reader`) |
| `homelab/edge` | `opnsense_api_key`, `opnsense_api_secret`, `pihole_password`, `cloudflared_<tunnel>_token` | `edge` |
| `homelab/grafana` | `admin_password`, `secret_key`, `oidc_client_id`, `oidc_client_secret` | `grafana` |
| `homelab/hosts/<host>/arcane` | `agent_token` | `docker_agent` |
| `homelab/identity` | `encryption_key` | `identity` |
| `homelab/menagerie` | `oidc_client_id`, `github_app_id` | `menagerie` |
| `homelab/nats/nsc` | `tgz`: the nsc stores and keys (operator, accounts, users) | `nats-user.fish` |
| `homelab/nats/server` | `resolver`: operator and account JWTs | `nats` |
| `homelab/nats/<user>` | `creds` | `nats` (`admin`), `clickhouse` (`clickhouse`), Trowel (`trowel`, through Wyrwood) |
| `homelab/ntfy` | `auth_users`, `auth_tokens` | ntfy's sidecar, through Wyrwood |
| `homelab/ntfy/<admin>` | `password` | the ntfy admin, for the ntfy apps |
| `homelab/ntfy/homelab` | `token` | publishers of topic `homelab` |
| `homelab/postgres/postgres` | `password` | `postgres` (only when it creates a data directory) |
| `homelab/runner` | `app_id`, `app_login` | the runner's entrypoint |
| `homelab/trowel/github/<owner>` | `webhook_secret` | Trowel, through Wyrwood |
| `homelab/wyrd` | `wyrwood_role_id`, `wyrwood_client_id`, `xolotl_client_id` | `wyrd` |
| `xolotl/nats` | `creds` | Xolotl, which reads its own `xolotl/` prefix |
| `workspace/ntfy` | `topic`, `url`, `token` | the workspaces' Dagu |

## Wyrwood

Controller `wyrwood.internal` (docker-infra); an agent on every Docker host. Bindings, as the agents report them:

| Host | Key | Policies | Access group |
| --- | --- | --- | --- |
| docker-infra | name `homelab-runner` | `homelab-runner` | 1502 `homelab-runner` |
| gtr6 | compose `menagerie/menagerie` | `menagerie` | 1000 `workspaces` |
| gtr6 | name `devcontainer-<slug>`, one per workspace | `workspace`, `xolotl-client-key` | 1000 `workspaces` |
| gtr6 | name `devcontainer-boblangley-dev` (additional policy) | `homelab-agent` | 1000 `workspaces` |
| ser6-max | compose `hermes/hermes` | `hermes-agent` | |
| wtr-pro | compose `ntfy/secrets`, directory `ntfy-secrets` | `ntfy`: read `kv/data/homelab/ntfy` | |
| wtr-pro | compose `trowel/trowel`, directory `trowel` | `trowel`: read `kv/data/homelab/nats/trowel` and `kv/data/homelab/trowel/github/*` | 1503 `trowel` |

Access groups 1502 and 1503 are created by role `wyrwood_agent` (`wyrwood_access_groups`); on gtr6 the agent was
added to `workspaces` by hand.

## NATS

Operator `homelab`; accounts `SYS` and `APP` (JetStream, unlimited). Users in `APP`, each with its permissions in its
user JWT:

| User | Publishes | Subscribes |
| --- | --- | --- |
| `admin` | anything | anything |
| `workspace` | anything | anything |
| `xolotl` | `xolotl.exchanges.>`, `$JS.API.STREAM.INFO.XOLOTL` | `_INBOX.>` |
| `clickhouse` | the `XOLOTL` consumer `clickhouse`'s API and acks | `_INBOX.>` |
| `trowel` | `github.>` | `_INBOX.>` |

Streams and consumers are declared in `host_vars` and kept by role `nats`.

## Cloudflare

Tunnels are remotely managed: role `edge` runs `cloudflared-<tunnel>` with its token, and the public hostnames are set
in the Cloudflare dashboard. The routes the roles here depend on, on tunnel `wyrd`:

| Hostname | Service |
| --- | --- |
| `ntfy.wyrd.team` | `HTTP` `ntfy.internal:8080` |
| `hooks.wyrd.team` | `HTTP` `trowel.internal:8080` |

## Backblaze B2

Bucket `wyrd-clickhouse` (`s3.us-west-004.backblazeb2.com`), private, for ClickHouse's archive and backups. Its
application key is limited to the bucket, with `listFiles`, `readFiles`, `writeFiles` and `deleteFiles`. Lifecycle
rules:

| Prefix | Hide after | Delete hidden after |
| --- | --- | --- |
| `backups/incr/` | 90 days | 1 day |
| `backups/full/` | 98 days | 1 day |
| `archive/` | never | 1 day |

## GitHub

- Organization `wyrd-company`: a webhook to `https://hooks.wyrd.team/github/wyrd-company`, JSON, signed with
  `homelab/trowel/github/wyrd-company`.
- The runner's GitHub App: its key is Transit `gh-app-homelab-runner`, its ID and login in `homelab/runner`.

## Pocket ID

`pocketid.internal`, role `identity`. OIDC clients for OpenBao, Wyrwood, Xolotl, Menagerie, Arcane and Grafana; their
client IDs are installation identifiers, in OpenBao. Groups the services check: `ssh_users` (SSH certificates),
`xolotl_admins` (Xolotl's admin UI), `grafana_admins` and `grafana_editors` (Grafana's Admin and Editor roles).

The Grafana client: callback URL `https://grafana.internal/login/generic_oauth`, PKCE on, and its allowed groups are
the people who may sign in (as Viewers, unless in a Grafana group). `scripts/openbao/grafana.fish` stores its ID and
secret.
