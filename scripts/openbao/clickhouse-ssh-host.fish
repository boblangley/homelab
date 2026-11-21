#!/usr/bin/env fish
# Provision the ClickHouse SSH host key in OpenBao.
# Prints the known_hosts entry for clickhouse.internal, reusing the stored key if present.

read --local --silent --prompt-str 'OpenBao root token: ' token
or exit 1
test -n "$token"
or exit 1
# Override the Wyrwood socket address a devcontainer may inherit.
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN "$token"
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN "$token"
set -e token

umask 077
set -l work (mktemp -d)
or exit 1
function clean_work --on-event fish_exit --inherit-variable work
    rm -rf -- "$work"
end

set -l key_path homelab/clickhouse/ssh-host
set -l key_file "$work/host"
set -l read_error (bao kv get -namespace=wyrwood -mount=kv -field=private_key $key_path 2>&1 >"$key_file")
if test $status -ne 0
    if not string match --quiet -- '*No value found*' "$read_error"
        printf '%s\n' $read_error >&2
        exit 1
    end
    rm -- "$key_file"
    ssh-keygen -q -t ed25519 -N '' -C clickhouse.internal -f "$key_file"
    or exit 1
    bao kv put -namespace=wyrwood -mount=kv -cas=0 $key_path "private_key=@$key_file" >/dev/null
    or exit 1
end

set -l public_key (ssh-keygen -y -f "$key_file")
or exit 1
if not string match --quiet -- 'ssh-ed25519 *' "$public_key"
    echo "$key_path must contain an Ed25519 private key." >&2
    exit 1
end
printf '[clickhouse.internal]:9022 %s\n' "$public_key"
