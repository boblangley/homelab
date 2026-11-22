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
| `wyrwood` | `transit` | Signing keys that never leave OpenBao, such as `homelab-ansible` (the `ansible` account's SSH key), `gh-app-homelab-runner` and each workspace's Deck identity, `deck-<workspace>` (`deck-client.fish`) |
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
| `homelab/deck/host` | `private_key`: Deck's SSH host key (`deck-bootstrap.fish`) | Deck, through Wyrwood |
| `homelab/clickhouse/<user>` | `password` | `clickhouse`, `otel_gateway` (`otel`), `grafana` (`reader`) |
| `homelab/clickhouse/ssh-host` | `private_key`: ClickHouse's OpenSSH Ed25519 host key (`clickhouse-ssh-host.fish`) | `clickhouse`, when a user has `ssh_public_key` |
| `homelab/edge` | `opnsense_api_key`, `opnsense_api_secret`, `pihole_password`, `cloudflared_<tunnel>_token` | `edge` |
| `homelab/grafana` | `admin_password`, `secret_key`, `oidc_client_id`, `oidc_client_secret` | `grafana` |
| `homelab/hosts/<host>/arcane` | `agent_token` | `docker_agent` |
| `homelab/identity` | `encryption_key` | `identity` |
| `homelab/menagerie` | `oidc_client_id`, `github_app_id` | `menagerie` |
| `homelab/nats/nsc` | `tgz`: the nsc stores and keys (operator, accounts, users) | `nats-user.fish` |
| `homelab/nats/server` | `resolver`: operator and account JWTs | `nats` |
| `homelab/nats/<user>` | `creds` | `nats` (`admin`), `clickhouse` (`clickhouse`), Trowel (`trowel`) and Deck (`deck`), through Wyrwood |
| `homelab/ntfy` | `auth_users`, `auth_tokens` | ntfy's sidecar, through Wyrwood |
| `homelab/ntfy/<admin>` | `password` | the ntfy admin, for the ntfy apps |
| `homelab/ntfy/homelab` | `token` | publishers of topic `homelab` |
| `homelab/postgres/postgres` | `password` | `postgres` (only when it creates a data directory) |
| `homelab/runner` | `app_id`, `app_login` | the runner's entrypoint |
| `homelab/trowel/github/<owner>` | `webhook_secret` | Trowel, through Wyrwood |
| `homelab/wyrd` | `wyrwood_role_id`, `wyrwood_client_id`, `xolotl_client_id` | `wyrd` |
| `deck/bots/<bot>` | `token`: the Discord bot's token, stored by hand (`WyrdBot`, named `wyrdbot` in Deck's config) | Deck, through Wyrwood |
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
| wtr-pro | compose `deck/deck`, directory `deck` | `deck`: read `kv/data/homelab/deck/host`, `kv/data/homelab/nats/deck` and `kv/data/deck/bots/*` | 1504 `deck` |

Access groups 1502, 1503 and 1504 are created by role `wyrwood_agent` (`wyrwood_access_groups`); on gtr6 the agent was
added to `workspaces` by hand.

Menagerie chooses each gtr6 workspace's policies, on its Policies screen and each workspace's **Policies**; templates
no longer declare them, and an edit made directly in Wyrwood is replaced at the workspace's next apply, start or
rebuild. Its operator key, `menagerie-gtr6-3` (offered as `menagerie-operator-3`), may read and bind `workspace`,
`xolotl-client-key`, `deck-client`, `operator-boblangley`, `operator-iradesa` and `homelab-agent` on gtr6; a binding
holding any other policy is hidden from it.

The Policies screen settings, saved on 2026-11-20:

- Required: `workspace`, `xolotl-client-key` and `deck-client`.
- Multi-select group `Operator`: `operator-boblangley` and `operator-iradesa`.
- Optional: `homelab-agent`.

On 2026-11-20 every workspace's binding held the required policies and at least one `Operator` policy, all conforming.

When these settings change: saving a newly required policy adds it to each stored selection, and queues an apply job
for each changed workspace whose folder exists. The save alone does not show that Wyrwood changed, so check each row
for a pending or failed apply. A group is enforced when a workspace is created, and an edit cannot leave a complete
group empty; an existing selection that already lacks a policy from a new group may stay without one through an edit.

Binding values (`xolotl_key_name`, `deck_key`): Menagerie keeps each value its 0.5.0 import took, from the workspace's
Wyrwood binding or, when it found none, from the workspace's legacy declaration. A value name a workspace does not
have yet takes the workspace's name when it is first needed. On 2026-11-20 every value was the workspace's name.

Templates are registered in Menagerie's interface and kept in its data volume, not in this repo. On a fresh volume,
register **Workspace**, id `workspace`, address `gh:wyrd-company/workspace-template@0.6.0`, and check that Validate
shows version `0.6.0`: without the tag Menagerie takes the newest version. 0.6.0 requires Menagerie 0.5.0 or later:
it asks for no Xolotl key policy and declares no policies, and takes its key's address from
`MENAGERIE_XOLOTL_KEY`, which Menagerie sets from `provisioning.xolotl.key-policy`. Earlier versions ask for the key
policy (answer `devcontainer`).

Policy `deck-client` signs as the workspace's Deck key, value `deck_key`. Its HCL:

```hcl
path "transit/keys/deck-{{binding.deck_key}}" { capabilities = ["read"] }
path "transit/sign/deck-{{binding.deck_key}}" { capabilities = ["update"] }
```

## ClickHouse SSH queries

Run `fish scripts/openbao/clickhouse-ssh-host.fish` and enter the OpenBao root token at its prompt. The script
connects to `https://openbao.internal:8200`, stores the server's private host key, and prints the public
`known_hosts` entry.

Keep the client key `clickhouse-read` in OpenBao Transit. Give its Wyrwood policy these permissions in the
`wyrwood` namespace.

```hcl
path "transit/keys/clickhouse-read" { capabilities = ["read"] }
path "transit/sign/clickhouse-read" { capabilities = ["update"] }
```

Configure the policy to offer `clickhouse-read` as an SSH agent identity. Allow Menagerie's operator key to
bind the policy and select it on the workspace that will run queries. After Menagerie applies the workspace
binding, check that `ssh-add -l` lists `clickhouse-read`.

Add a user to `clickhouse_users` in `host_vars/wtr-pro.internal.yml`. Replace `<OpenSSH public key>` with the
client key's public line, including its key type. This account reads the two databases the homelab writes to.

```yaml
- name: ssh_reader
  ssh_public_key: <OpenSSH public key>
  profile: readonly
  grants:
    - GRANT SELECT ON otel.*
    - GRANT SELECT ON xolotl.*
```

Apply. The SSH listener runs on port 9022 inside the homelab overlay. ClickHouse also accepts its existing
password accounts on this port, subject to the same database grants and network restrictions.

In the authorized workspace, add the printed host key entry to `~/.ssh/known_hosts`. Save the public line
ending in `clickhouse-read` from `ssh-add -L` to `~/.ssh/clickhouse-read.pub`. Select that identity explicitly
when you connect so that the SSH agent signs with the intended key.

```sh
ssh -p 9022 -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o IdentitiesOnly=yes -i ~/.ssh/clickhouse-read.pub \
  ssh_reader@clickhouse.internal 'SELECT currentUser()'
```

Expect `ssh_reader`.

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
| `deck` | `deck.>`, `$KV.deck-threads.>`, `$JS.FC.>`, `$JS.API.INFO`, and the JetStream API of stream `DECK` and bucket `deck-threads` only (`deck-bootstrap.fish` lists them) | `_INBOX.>`, `$KV.deck-threads.>` |

To widen a user, `nats-user.fish <user> --update --pub ... --sub ...` adds subjects to its allow lists and issues a
new JWT for the same key; restart the service that uses it. It only adds, and it refuses a direction with no allow
list (`admin` and `workspace`), where adding would restrict the user. Removing a subject means revoking the old JWT
(`nsc revocations`).

Streams and consumers are declared in `host_vars` and kept by role `nats`, except Deck's stream `DECK` and bucket
`deck-threads`, which Deck creates and corrects itself at start.

## Deck

Role `deck` runs the service on wtr-pro as `deck.internal:2222` (SSH, on the overlay). Bot `wyrdbot` is a Discord
application with the Message Content intent, installed in each server with the `bot` scope; in each granted
channel it needs View Channel, Send Messages, Send Messages in Threads, Create Public Threads, Create Polls, Embed
Links, Attach Files and Read Message History: permissions integer `563259191184384` in the install link
`https://discord.com/oauth2/authorize?client_id=<application id>&scope=bot&permissions=563259191184384`. A bot
missing from the server makes `deck channels` fail with `PermissionDenied`, the same answer as a missing grant.

Setting it up, once:

1. `fish scripts/openbao/deck-bootstrap.fish`: stores the host key and issues NATS user `deck`. Keep the public line
   it prints: clients pin it as `service.host_key`.
2. In Wyrwood, create policy `deck` (the reads above) and bind compose `deck/deck` on wtr-pro, directory `deck`,
   access group 1504. Create policy `deck-client` (above).
3. Apply.

When this repo widens user `deck` later (as it did with `$JS.API.INFO`), don't re-run `deck-bootstrap.fish`, which
refuses once the host key exists; add the subjects with `nats-user.fish deck --update --pub ...` and restart Deck.

Onboarding a workspace:

1. `fish scripts/openbao/deck-client.fish <workspace>`: creates Transit key `deck-<workspace>` and prints its
   `deck_keys` entry.
2. Add the entry to `deck_keys` in `host_vars/wtr-pro.internal.yml` with its grants (bot, server ID, and the IDs of
   the channels it may post in, not of threads; or `["*"]` for the whole server), and Apply; Deck restarts.
3. A Menagerie workspace on gtr6 already has policy `deck-client`, as it is required, with value `deck_key` set to
   its name: check that its row in Menagerie shows the policy applied. Any other binding gets policy `deck-client`
   with value `deck_key: <workspace>` in Wyrwood. Its `deck` CLI then works with the client config from the
   workspace dotfiles: `deck channels` lists what it was granted.

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
