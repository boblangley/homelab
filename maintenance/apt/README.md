# APT maintenance

Run the collector from a workspace with Ansible, Dagu, Python 3.12 or newer with SQLite 3.37 or newer, and SSH access to the selected hosts. The collector uses `python3-apt` on each host. The default target is `m1-1295.internal`.

## Set up the workspace

Save a private settings file on a persistent workspace mount. In this workspace, `/workspace/homelab/references/planning/` is Git-ignored and survives a rebuild. For example, create `apt-workspace.yml` there with these settings.

```yaml
state_dir: /workspace/homelab/references/planning/apt-state
ssh_auth_sock: /run/wyrwood/ssh-agent.sock
apt_hosts: m1-1295.internal
# apt_schedule: '0 8 * * *'
```

Use the workspace's dedicated SSH agent socket. From the clean, pull-only `main` checkout, fast-forward to `origin/main` and run setup with the same settings file each time.

```sh
ansible-playbook maintenance/setup-workspace.yml \
  -e maintenance_settings_file=/workspace/homelab/references/planning/apt-workspace.yml
```

Setup exports the reviewed commit to `<state dir>/revisions/<commit>/`. It imports that revision's [graph records](../graph/) into `graph.sqlite3` and renders `<state dir>/homelab-apt-collect.yaml`. The DAG uses the exported files until the next setup. Snapshots and decisions stay in the state directory across graph imports.

The rendered DAG supports manual runs. Automatic discovery in this workspace requires enabling `dag_discovery.symlinks` through the devcontainer's Dagu configuration and adding an individual file symlink plus its wiki page through the workflows repository's GitPR process. Link `homelab-apt-collect.yaml` beneath `/workflows/local/dags/` to the rendered file. Once discovery is configured, set `apt_schedule` in the private settings file and rerun setup to publish the schedule.

## Collect and triage

Run the rendered DAG manually with the workspace Dagu configuration.

```sh
dagu start -c /etc/dagu/config.yml /workspace/homelab/references/planning/apt-state/homelab-apt-collect.yaml
```

The collector refreshes APT indexes and saves one dated JSON snapshot per successful host under `apt/<host>/` in the state directory. Each snapshot records the deployed revision, lists all available updates, and shows candidates that are new, changed, or no longer listed compared with the previous readable snapshot. Triage checks the full candidate list for entries without a decision, including after a missed review. Consult the Dagu result for failed hosts and `unreadable_snapshots` for skipped history.

Start a Codex session from `maintenance/apt/` in the checkout of that revision and use [`apt-triage`](.agents/skills/apt-triage/SKILL.md). Give it the private state path, the Dagu run ID, each snapshot to review, and the next agreed window if it is set.

## Private handoff

Triage writes `apt/<host>/decisions/<snapshot-stem>.md` under the state directory. The operator passes the snapshot and decision file privately to the workstation session and identifies its local private state directory. Keep live snapshots, decisions, and run logs in private state outside the checkout. The workstation session writes its result to `apt/<host>/updates/<window-id>.md` there. Issues and PRs carry shareable procedure changes.

## Plan and verify an update

Generate the graph from the revision named in the triage handoff. Run these commands from the workstation's checkout of that revision.

```sh
mkdir -p -m 700 ~/.local/state/homelab-maintenance
python3 maintenance/graph/import-graph.py ~/.local/state/homelab-maintenance/graph.sqlite3
```

Start a separate Codex session from `maintenance/apt/` on the operator workstation. Use [`apt-update`](.agents/skills/apt-update/SKILL.md) with the private handoff and dependency graph. Generate the proposed transaction from APT and review it with the operator. The agent runs the approved command in an interactive SSH session by default. If the plan would make the agent unable to finish, such as by taking its Xolotl gateway offline, the operator takes over before the update starts. Record what changed and verify the affected services.

Start package changes and planned restarts in the predefined weekly window or an expedited window agreed with the operator. Record its start, end, and time zone in the plan.
