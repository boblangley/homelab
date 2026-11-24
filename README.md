# homelab

Ansible for my homelab. This repo describes how each managed host is configured now; git history covers how it got there.

## What is managed where

| Kind | Managed by | Lives in |
| --- | --- | --- |
| Host configuration and core services | Ansible, from this repo | host config, `/opt/docker/<project>` |
| Sandboxes | Arcane, or Menagerie for workspaces | `/srv/docker-agent/arcane/projects/<project>` |
| Secrets | OpenBao, read by Ansible at run time | never in this repo |

Neither side changes the other's area.

## What may be published

This repo is public. Names may appear in it: hosts, accounts, OpenBao paths, Transit keys, policies. Values never
do: secrets, tokens, private keys, and identifiers particular to an installation, such as AppRole role IDs and OIDC
client IDs. Those live in OpenBao, and roles read them at run time.

## Layout

- `inventory/hosts.yml`: managed hosts.
- `host_vars/<host>.yml`: what is particular to each host.
- `roles/`: one role per concern. `base` applies to every host.
- `site.yml`: the playbook.
- `docs/external.md`: what the roles depend on that is configured by hand outside Ansible (OpenBao, Wyrwood, NATS
  users, Deck, Cloudflare, B2, GitHub, Pocket ID).
- `scripts/openbao/`: scripts that put secrets into OpenBao. Each asks for the token and prints only lengths and
  results.

## Run

The [Apply workflow](.github/workflows/apply.yml) runs the playbook when a push to `main` changes deployment inputs.
The self-hosted runner on docker-infra connects as `ansible` and reads OpenBao through its Wyrwood socket. Run Apply
by hand with `preview` for a check-mode run with diffs.

From a workstation, it connects as `agent`, which has passwordless sudo on each host, and reads OpenBao with the
operator's own token: `bao login -method=oidc` (Pocket ID) writes it to `~/.vault-token`.

The `boblangley-dev` workspace also connects as `agent`, using the dedicated `homelab-agent` OpenBao Transit key
through its Wyrwood binding. The `agent` account authorizes both the operator's key and this workspace key; the
private Transit key stays in OpenBao. The `homelab-agent` Wyrwood policy must remain exclusive to that workspace.

To apply only automation SSH authorized keys, without reading secrets or changing services:

```sh
~/.local/share/venvs/ansible/bin/ansible-playbook site.yml --tags automation_keys --skip-tags always
```

```sh
python3 -m venv ~/.local/share/venvs/ansible
~/.local/share/venvs/ansible/bin/pip install ansible-core
~/.local/share/venvs/ansible/bin/ansible-galaxy collection install -r requirements.yml

~/.local/share/venvs/ansible/bin/ansible-playbook site.yml --check --diff --skip-tags runner   # preview
~/.local/share/venvs/ansible/bin/ansible-playbook site.yml --skip-tags runner
```

## Adding a host

A fresh host has only the installer's account and a password, so its first step is by hand. As that account, with `sudo`:

1. Create `agent` (uid 1500) with the operator's public key in `~agent/.ssh/authorized_keys` and `agent ALL=(ALL) NOPASSWD: ALL` in `/etc/sudoers.d/agent`.
2. Add the host to `inventory/hosts.yml` and give it a `host_vars` file.
3. Run the playbook from a workstation, limited to the new host: `ansible-playbook site.yml --limit <host> --skip-tags runner`. It turns off password login, so step 1 must work first. The Apply workflow connects as `ansible`, which this first run creates, so until then Apply reports the host unreachable.
4. For a Docker worker, add it to `edge_socket_proxies` (docker-infra) only after that run has started its socket proxy.
