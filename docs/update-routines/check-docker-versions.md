# Check Docker versions

Run this check before planning Docker maintenance and again after the update to verify which version each node is running. Run the commands from the root of this repo with [Ansible and SSH access](../../README.md#run) to the managed hosts.

1. Check Swarm membership, node readiness, and the running Docker Engine versions from the manager.

   ```sh
   ssh -o BatchMode=yes -o UserKnownHostsFile="$PWD/known_hosts" \
     -o StrictHostKeyChecking=yes agent@docker-infra.internal \
     'sudo -n docker node ls --format "table {{.Hostname}}\t{{.Status}}\t{{.EngineVersion}}"'
   ```

2. Compare installed packages with the candidates in each host's local APT index. The index reflects the last refresh on that host. Ansible labels successful ad hoc commands `CHANGED` by default. This command reads package metadata.

   ```bash
   (
     set -o pipefail
     ansible docker -m ansible.builtin.command \
       -a 'apt-cache policy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras' |
       sed -En '/ \| |^[^[:space:]].*:$|^[[:space:]]+(Installed|Candidate):/p'
   )
   ```

3. Compare the host lists with the [inventory](../../inventory/hosts.yml). Check that every node reports `Ready` and every host returned package results. For each installed package, compare `Installed` with `Candidate`. `Installed: (none)` means the package is absent. Record version differences and any missing or unreachable hosts with the date of the check. After maintenance, compare the running Engine versions against the intended version on the hosts you updated.

[Return to the update inventory](../update-inventory.md)
