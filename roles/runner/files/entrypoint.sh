#!/usr/bin/env bash
# Registers one just-in-time runner, runs one job, and exits; the container's restart policy starts the next.
#   RUNNER_REPO    owner/repo the runner serves
#   RUNNER_LABELS  comma-separated labels besides self-hosted
set -euo pipefail

sock=/run/wyrwood/vault.sock
for _ in $(seq 60); do
    [ -S "$sock" ] && break
    sleep 2
done
[ -S "$sock" ] || { echo "No Wyrwood socket at $sock" >&2; exit 1; }

# Ansible's OpenBao library speaks HTTP only. Expose the socket to this container alone; Wyrwood adds the token.
socat TCP-LISTEN:8200,bind=127.0.0.1,reuseaddr,fork "UNIX-CONNECT:$sock" &

openbao() { curl -fsS --unix-socket "$sock" "http://openbao/v1/$1"; }

app=$(openbao kv/data/homelab/runner)
app_id=$(jq -r .data.data.app_id <<<"$app")
app_login=$(jq -r .data.data.app_login <<<"$app")

config_dir=$(mktemp -d)
cat > "$config_dir/config.yml" <<EOF
agent_addr: unix://$sock
apps:
  "$app_login":
    app_id: $app_id
    transit_key: gh-app-homelab-runner
EOF

token=$(GH_VAULT_APP_TOKEN_CONFIG="$config_dir/config.yml" gh-vault-agent-app-token --login "$app_login" --repo "$RUNNER_REPO")
rm -rf "$config_dir"

name="homelab-$(hostname)-$(date +%s)"
labels=$(jq -cn --arg l "$RUNNER_LABELS" '$l | split(",")')
jit=$(curl -fsS -X POST \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$RUNNER_REPO/actions/runners/generate-jitconfig" \
    -d "$(jq -cn --arg name "$name" --argjson labels "$labels" \
        '{name: $name, runner_group_id: 1, labels: $labels, work_folder: "_work"}')" \
    | jq -r .encoded_jit_config)
unset token

echo "Registered $name; waiting for a job."
cd /home/runner
exec ./run.sh --jitconfig "$jit"
