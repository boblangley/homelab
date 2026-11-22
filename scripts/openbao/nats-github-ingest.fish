#!/usr/bin/env fish
# Add the isolated GitHub ingestion account to an existing NATS operator store. Run from an operator workstation.
# The account JWTs expose only the source stream's mirror protocol to GITHUB_INGEST.

read --silent --prompt-str 'OpenBao root token: ' token; or exit 1
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token

function kv
    bao kv $argv[1] -namespace=wyrwood -mount=kv $argv[2..]
end

set work (mktemp -d /dev/shm/nats-github-ingest.XXXXXX); or exit 1
function cleanup --on-event fish_exit
    find "$work" -maxdepth 1 -type f -exec shred -u {} +
    rmdir "$work"
end

kv get -format=json homelab/nats/nsc > "$work/store.json"; or exit 1
set store_version (jq -er '.data.metadata.version' "$work/store.json"); or exit 1
set resolver_version (kv get -format=json homelab/nats/server | jq -er '.data.metadata.version'); or exit 1

# The existing archive holds the stores and their signing keys. Keep the regenerated store in OpenBao
# before publishing the derived credentials and resolver so a retry uses the same account and keys.
set inner '
set -eu
export NKEYS_PATH=/nsc/keys NSC_HOME=/nsc/nsc XDG_CONFIG_HOME=/nsc/.config XDG_DATA_HOME=/nsc
base64 -d | tar xz -C /nsc
nsc env -s /nsc/stores >&2
mkdir /nsc/out
account=GITHUB_INGEST

add_link() {
    subject=$1
    local_subject=$2
    shift 2
    nsc add export -a APP --private --subject "$subject" "$@" >&2
    nsc generate activation -a APP --subject "$subject" --target-account "$account" -o /nsc/activation.jwt >&2
    nsc add import -a "$account" --token /nsc/activation.jwt --local-subject "$local_subject" >&2
    rm /nsc/activation.jwt
}

if ! nsc describe account -n "$account" >/dev/null 2>&1; then
    nsc add account "$account" >&2
    nsc edit account "$account" --js-enable 1 >&2
    add_link "\$JS.API.CONSUMER.CREATE.GITHUB" "APP.GITHUB.API.CONSUMER.CREATE.GITHUB" --service
    add_link "\$JS.FC.GITHUB.>" "\$JS.FC.GITHUB.>" --service
    add_link "github-mirror.>" "github-mirror.>"
    nsc add user -a "$account" github-admin >&2
    nsc add user -a "$account" clickhouse-github \
        --allow-pub "\$JS.API.CONSUMER.MSG.NEXT.GITHUB.clickhouse,\$JS.API.CONSUMER.INFO.GITHUB.clickhouse,\$JS.API.STREAM.INFO.GITHUB,\$JS.ACK.GITHUB.clickhouse.>" \
        --allow-sub "_INBOX.>" >&2
fi
for user in github-admin clickhouse-github; do
    nsc generate creds -a "$account" -n "$user" -o "/nsc/out/$user.creds" >&2
done
nsc generate config --mem-resolver --sys-account SYS > /nsc/out/resolver.conf
tar czf /nsc/out/nsc.tgz -C /nsc stores keys nsc
tar -C /nsc/out -c .
'

jq -er '.data.data.tgz' "$work/store.json" | docker run --rm -i --tmpfs /nsc:mode=0700 \
    natsio/nats-box:0.20.2 sh -c "$inner" > "$work/account.tar"
set result $pipestatus
if test "$result[1]" -ne 0; or test "$result[2]" -ne 0
    echo "Could not prepare the GitHub ingestion account. OpenBao is unchanged." >&2
    exit 1
end

tar -xf "$work/account.tar" -C "$work"; or exit 1
for file in nsc.tgz resolver.conf github-admin.creds clickhouse-github.creds
    test -s "$work/$file"; or exit 1
end
grep -q '^resolver: MEMORY' "$work/resolver.conf"; or exit 1
base64 -w0 "$work/nsc.tgz" > "$work/nsc.b64"; or exit 1

kv put -cas="$store_version" homelab/nats/nsc tgz=@"$work/nsc.b64" >/dev/null; or exit 1
for user in github-admin clickhouse-github
    kv put "homelab/nats/$user" creds=@"$work/$user.creds" >/dev/null; or exit 1
end
kv put -cas="$resolver_version" homelab/nats/server resolver=@"$work/resolver.conf" >/dev/null; or exit 1
echo "Stored the GITHUB_INGEST account, credentials, and NATS resolver."
