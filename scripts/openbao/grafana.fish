#!/usr/bin/env fish
# Stores Grafana's secrets in OpenBao (namespace wyrwood, kv homelab/grafana), where role grafana reads them:
# admin_password and secret_key are generated the first time and then kept (a new secret_key would make Grafana's
# stored data source secrets unreadable); oidc_client_id and oidc_client_secret, from Grafana's client in Pocket ID, are
# asked for without echoing. Stops on any OpenBao error. Prints only lengths.
#   fish scripts/openbao/grafana.fish

set path homelab/grafana

read --silent --prompt-str 'OpenBao root token: ' token
# BAO_* as well: bao prefers them, and a devcontainer may set BAO_ADDR to its Wyrwood socket.
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token

function cleanup
    set -e BAO_TOKEN VAULT_TOKEN client_id client_secret stored_admin_password stored_secret_key stored want
end

function kv_field -a field
    bao kv get -namespace=wyrwood -mount=kv -field=$field $path 2>/dev/null
end

# Tells "not stored yet" from an error, so a failed read never leads to a new secret_key.
set probe (bao kv get -namespace=wyrwood -mount=kv $path 2>&1 >/dev/null)
set probe_status $status
if test $probe_status -ne 0; and not string match --quiet '*No value found*' -- "$probe"
    echo "Can't read $path from $BAO_ADDR; nothing stored. OpenBao said:"
    printf '%s\n' $probe
    cleanup
    exit 1
end

# 40 characters from [A-Za-z0-9]: safe in Grafana's $__file{} values, which also expand $.
function random40
    openssl rand -base64 60 | string join '' | string replace --all --regex '[^A-Za-z0-9]' '' | string sub --length 40
end

# Kept if already in OpenBao, otherwise generated.
function existing_or_new -a field
    set value (kv_field $field)
    if test -n "$value"
        echo "$field: already in OpenBao, kept" >&2
    else
        set value (random40)
        echo "$field: generated (length "(string length -- "$value")")" >&2
    end
    echo $value
end
set stored_admin_password (existing_or_new admin_password)
set stored_secret_key (existing_or_new secret_key)
if test (string length -- "$stored_admin_password") -lt 16; or test (string length -- "$stored_secret_key") -lt 16
    echo "couldn't read or generate admin_password and secret_key; nothing stored."
    cleanup
    exit 1
end

read --silent --prompt-str 'Pocket ID client ID for Grafana: ' client_id
read --silent --prompt-str 'Pocket ID client secret for Grafana: ' client_secret
for v in client_id client_secret
    if test (string length -- "$$v") -lt 16; or string match --quiet --regex '[\s$]' -- "$$v"
        echo "$v doesn't look right; nothing stored."
        cleanup
        exit 1
    end
end

if not bao kv put -namespace=wyrwood -mount=kv $path \
        admin_password=$stored_admin_password secret_key=$stored_secret_key \
        oidc_client_id=$client_id oidc_client_secret=$client_secret >/dev/null
    echo "Writing $path failed; see OpenBao's error above."
    cleanup
    exit 1
end

# Both sides quoted: an empty read-back must not reach test's error message, which would print the value.
for field in admin_password secret_key oidc_client_id oidc_client_secret
    switch $field
        case admin_password
            set want $stored_admin_password
        case secret_key
            set want $stored_secret_key
        case oidc_client_id
            set want $client_id
        case oidc_client_secret
            set want $client_secret
    end
    set stored (kv_field $field)
    if test "$stored" = "$want"
        echo "$field: stored (length "(string length -- "$want")")"
    else
        echo "$field: read-back DIFFERS"
    end
end
cleanup
