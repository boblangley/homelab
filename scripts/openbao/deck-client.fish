#!/usr/bin/env fish
# Gives one workspace its Deck identity: Transit key deck-<workspace> (ed25519, namespace wyrwood, mount transit),
# which never leaves OpenBao. The workspace's Wyrwood binding signs with it through policy deck-client (value
# deck_key: <workspace>). Prints the public line, as `deck config key` would, and the entry to add to deck_keys in
# host_vars/wtr-pro.internal.yml, with the bots configured; the grants are yours to fill in. A key that exists is
# reused, not replaced.
#   fish scripts/openbao/deck-client.fish <workspace>

set name $argv[1]
if not string match --quiet --regex '^[a-z0-9][a-z0-9-]{0,57}$' -- "$name"
    echo "usage: fish scripts/openbao/deck-client.fish <workspace>"
    exit 2
end
set key deck-$name

read --silent --prompt-str 'OpenBao root token: ' token
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token
function fail
    echo $argv
    set -e -g BAO_TOKEN VAULT_TOKEN
    exit 1
end

set info (bao read -namespace=wyrwood -format=json transit/keys/$key 2>/dev/null | string collect)
if test -z "$info"
    bao write -namespace=wyrwood transit/keys/$key type=ed25519 >/dev/null; or fail "couldn't create transit/keys/$key."
    set info (bao read -namespace=wyrwood -format=json transit/keys/$key | string collect)
    echo "created transit/keys/$key"
else
    echo "transit/keys/$key exists; using it"
end
set -e -g BAO_TOKEN VAULT_TOKEN

# The latest version's raw ed25519 public key, as an OpenSSH line with deck's comment, deck:<key>.
set line (printf '%s' $info | python3 -I -c '
import base64, json, struct, sys
d = json.load(sys.stdin)["data"]
if d["type"] != "ed25519":
    sys.exit("transit key %s is %s, not ed25519" % (sys.argv[1], d["type"]))
raw = base64.b64decode(d["keys"][str(d["latest_version"])]["public_key"])
t = b"ssh-ed25519"
blob = struct.pack(">I", len(t)) + t + struct.pack(">I", len(raw)) + raw
print("ssh-ed25519 %s deck:%s" % (base64.b64encode(blob).decode(), sys.argv[1]))
' $key); or fail "couldn't read the public key."

echo
echo "Add to deck_keys in host_vars/wtr-pro.internal.yml, with its grants, and Apply:"
echo "  - name: $name"
echo "    public_key: $line"
echo "    grants:"
# The bots in deck_bots, to choose from, as Ansible sees them; none listed if it can't say.
# From the repo's root, where ansible.cfg is; fish has no subshell, so pushd and popd.
pushd (status dirname)/../..
set bots (ansible-inventory --host wtr-pro.internal 2>/dev/null \
    | python3 -I -c 'import json, sys; print(", ".join(b["name"] for b in json.load(sys.stdin).get("deck_bots", [])))' \
    2>/dev/null)
popd
if test -n "$bots"
    echo "      - bot: <bot>  # one of: $bots"
else
    echo "      - bot: <bot>"
end
echo "        server: \"<server id>\""
echo "        channels:"
echo "          - \"<channel id>\""
