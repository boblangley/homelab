#!/usr/bin/env fish
# ntfy's users and tokens (an admin, and users homelab and workspaces), in OpenBao (namespace wyrwood, kv):
#   homelab/ntfy             auth_users, auth_tokens: what the server loads (bcrypt hashes and tokens only)
#   homelab/ntfy/<admin>     password: the admin's login for the ntfy apps (read it with bao kv get)
#   homelab/ntfy/homelab     token: publishes to topic homelab (the homelab's own alerts)
#   workspace/ntfy           url and token added (patch; its topic field is kept): publishes to topic workspaces
# Users homelab and workspaces get random passwords nobody keeps; they use only their tokens. Hashes and tokens come
# from the ntfy image (`ntfy user hash`, `ntfy token generate`), passwords on stdin. Stops without changing anything
# if homelab/ntfy exists already. Reads everything back. Prints only lengths and results.
#   fish scripts/openbao/ntfy-users.fish

set image binwiederhier/ntfy:v2.38.0

read --prompt-str 'ntfy admin username: ' admin
if not string match --quiet --regex '^[a-z][a-z0-9_-]{0,31}$' -- "$admin"
    echo "usernames are lowercase letters, digits, - and _"
    exit 2
end

read --silent --prompt-str 'OpenBao root token: ' token
# BAO_* as well: bao prefers them, and a devcontainer may set BAO_ADDR to its Wyrwood socket.
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token
function kv
    bao kv $argv[1] -namespace=wyrwood -mount=kv $argv[2..]
end
function fail
    echo $argv
    set -e -g BAO_TOKEN VAULT_TOKEN
    exit 1
end

# 0: stored; 1: not stored; 2: OpenBao refused or couldn't be reached (error printed). A failed read must never be
# taken for "not stored", which would go on to create and overwrite.
function kv_exists -a p
    set err (bao kv get -namespace=wyrwood -mount=kv $p 2>&1 >/dev/null)
    and return 0
    string match --quiet '*No value found*' -- "$err"; and return 1
    printf '%s\n' $err >&2
    return 2
end
kv_exists homelab/ntfy
switch $status
    case 0
        fail "homelab/ntfy exists already; nothing changed."
    case 2
        fail "Can't read homelab/ntfy from $BAO_ADDR; nothing changed."
end

function newpw
    openssl rand -base64 60 | string join '' | string replace --all --regex '[^A-Za-z0-9]' '' | string sub --length 32
end
function hash
    printf '%s\n%s\n' $argv[1] $argv[1] | docker run --rm -i $image user hash 2>/dev/null
end
function newtoken
    docker run --rm $image token generate
end

set admin_pw (newpw)
set admin_hash (hash $admin_pw)
set homelab_hash (hash (newpw))
set workspaces_hash (hash (newpw))
set homelab_token (newtoken)
set workspaces_token (newtoken)

for h in $admin_hash $homelab_hash $workspaces_hash
    string match --quiet --regex '^\$2a\$10\$.{53}$' -- "$h"; or fail "a password hash came out wrong; nothing stored."
end
for t in $homelab_token $workspaces_token
    string match --quiet --regex '^tk_[a-z0-9]{29}$' -- "$t"; or fail "a token came out wrong; nothing stored."
end
test (string length -- $admin_pw) -eq 32; or fail "couldn't make the admin's password; nothing stored."

set users "$admin:$admin_hash:admin,homelab:$homelab_hash:user,workspaces:$workspaces_hash:user"
set tokens "homelab:$homelab_token:alerts,workspaces:$workspaces_token:dagu"

kv put homelab/ntfy auth_users=$users auth_tokens=$tokens >/dev/null
kv put homelab/ntfy/$admin password=$admin_pw >/dev/null
kv put homelab/ntfy/homelab token=$homelab_token >/dev/null
kv patch workspace/ntfy url=https://ntfy.wyrd.team token=$workspaces_token >/dev/null

set bad 0
# Quoted: an empty read-back must not reach test's error message, which would print the value.
test "$(kv get -field=auth_users homelab/ntfy)" = "$users"; or set bad 1
test "$(kv get -field=auth_tokens homelab/ntfy)" = "$tokens"; or set bad 1
test "$(kv get -field=password homelab/ntfy/$admin)" = "$admin_pw"; or set bad 1
test "$(kv get -field=token homelab/ntfy/homelab)" = "$homelab_token"; or set bad 1
test "$(kv get -field=token workspace/ntfy)" = "$workspaces_token"; or set bad 1
kv get -field=topic workspace/ntfy >/dev/null 2>&1; or set bad 1
if test $bad -eq 0
    echo "stored: homelab/ntfy (3 users, 2 tokens), homelab/ntfy/$admin (password length 32), homelab/ntfy/homelab,"
    echo "        workspace/ntfy url and token (topic kept)"
else
    echo "read-back DIFFERS somewhere"
end
set -e admin_pw admin_hash homelab_hash workspaces_hash homelab_token workspaces_token users tokens
set -e BAO_TOKEN VAULT_TOKEN
