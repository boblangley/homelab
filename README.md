# homelab

Ansible for my homelab. This repo describes how each managed host is configured now; git history covers how it got there.

## What is managed where

| Kind | Managed by | Lives in |
| --- | --- | --- |
| Host configuration and core services | Ansible, from this repo | host config, `/opt/docker/<project>` |
| Sandboxes | Arcane, or Menagerie for workspaces | `/srv/docker-agent/arcane/projects/<project>` |
| Secrets | OpenBao, read by Ansible at run time | never in this repo |

Neither side changes the other's area.

## Layout

- `inventory/hosts.yml`: managed hosts.
- `host_vars/<host>.yml`: what is particular to each host.
- `roles/`: one role per concern. `base` applies to every host.
- `site.yml`: the playbook.

## Run

Ansible runs from a workstation for now. It connects as `agent`, which has passwordless sudo on each host.

```sh
python3 -m venv ~/.local/share/venvs/ansible
~/.local/share/venvs/ansible/bin/pip install ansible-core
~/.local/share/venvs/ansible/bin/ansible-galaxy collection install -r requirements.yml

~/.local/share/venvs/ansible/bin/ansible-playbook site.yml --check --diff   # preview
~/.local/share/venvs/ansible/bin/ansible-playbook site.yml
```

## Adding a host

A fresh host has only the installer's account and a password, so its first step is by hand. As that account, with `sudo`:

1. Create `agent` (uid 1500) with the operator's public key in `~agent/.ssh/authorized_keys` and `agent ALL=(ALL) NOPASSWD: ALL` in `/etc/sudoers.d/agent`.
2. Add the host to `inventory/hosts.yml` and give it a `host_vars` file.
3. Run the playbook. It turns off password login, so step 1 must work first.
