# APT maintenance

Run the collector from a workspace with Ansible, Dagu, Python with SQLite 3.37 or newer, and SSH access to the selected hosts. The collector uses `python3-apt` on each host. Start with `m1-1295.internal` and set `maintenance_apt_hosts` to an Ansible inventory pattern when you want a different scope.

## Set up the workspace

Run this from the root of a reviewed homelab checkout.

```sh
ansible-playbook maintenance/setup-workspace.yml
```

The playbook runs on the workspace. It imports the checked-in [graph records](../graph/) into `graph.sqlite3` and renders `homelab-apt-collect.yaml` in `~/.local/state/homelab-maintenance`. Set `maintenance_state_dir` to choose another private path outside the Git checkout. SQLite is generated from the JSONL records. Edit the records to change the graph, and rerun setup to regenerate SQLite. Snapshots stay in the state directory across graph imports.

For Dagu discovery, enable `dag_discovery.symlinks` in the local Dagu configuration and set `maintenance_dag_dir` to the workspace's DAG directory when running setup. Setup links the rendered file from there. To schedule collection, set `maintenance_apt_schedule` to the desired cron expression in the workspace's setup variables. The default renders a manual DAG. Run setup after pulling changes to the checkout it uses.

## Collect and triage

Run the rendered DAG manually with the workspace Dagu configuration.

```sh
dagu start -c /etc/dagu/config.yml ~/.local/state/homelab-maintenance/homelab-apt-collect.yaml
```

The collector refreshes APT indexes and saves one dated JSON snapshot per successful host under `apt/<host>/` in the state directory. Each snapshot lists all available updates and shows candidates that are new, changed, or no longer listed compared with the previous successful snapshot. A failed host appears in the Dagu run log. Use its last saved snapshot as stale evidence.

Start a workspace session from `maintenance/apt/` and use [`apt-triage`](.agents/skills/apt-triage/SKILL.md) with the snapshot and Dagu result. The skill describes which advisories and changelogs to consult. This version hands the snapshot to the triage session manually.

## Plan and verify an update

Generate the graph from the workstation's checkout of the same revision. Run these commands from the repository root.

```sh
mkdir -p -m 700 ~/.local/state/homelab-maintenance
python3 maintenance/graph/import-graph.py ~/.local/state/homelab-maintenance/graph.sqlite3
```

Start a separate session from `maintenance/apt/` on the operator workstation. Use [`apt-update`](.agents/skills/apt-update/SKILL.md) with the triage decision, snapshot, and dependency graph. Generate the proposed transaction from APT on the target hosts and review it with the operator. Record what changed and verify the affected services after an approved update.
