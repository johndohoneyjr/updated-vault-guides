#!/usr/bin/env bash
set -x

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT $0: $1"
}


vault login password

logger "Write generic secrets in Vault"
vault kv put secret/me username=${OKTA_USERNAME} password=supersecret
vault secrets enable -path=supersecret generic
vault kv put supersecret/admin admin_user=root admin_password=P@55w3rd
vault secrets enable -path=verysecret generic
vault kv put verysecret/sensitive key=value password=35616164316lasfdasfasdfasdfasdfasf

logger "Create Vault policies"
echo '
path "sys/mounts" {
 capabilities = ["list","read"]
}
path "secret/*" {
 capabilities = ["list", "read"]
}
path "secret/me" {
 capabilities = ["create", "read", "update", "delete", "list"]
}
path "supersecret/" {
 capabilities = ["list", "read"]
}
path "supersecret/admin" {
 capabilities = ["list", "read"]
 mfa_methods = ["okta"]
}
path "ssh-client-signer/*" {
 capabilities = ["read","list","create","update"]
}
path "aws/*" {
 capabilities = ["read","list","create","update"]
}
path "ssh/*" {
 capabilities = ["read","list","create","update"]
}'  | vault policy write okta -

logger "Enable Okta backend in Vault"
vault auth enable okta

logger "Configure Okta backend in Vault"
vault kv put auth/okta/config \
  organization="${OKTA_ORG}" \
  base_url="${OKTA_BASE_URL}" \
  api_token="${OKTA_API_TOKEN}"
#vault kv put auth/okta/users/${OKTA_USERNAME} policies=okta

logger "Attach okta policies to okta group"
vault kv put auth/okta/groups/okta policies=okta
export OKTA_ACCESSOR=$(curl --header "X-Vault-Token: password"  http://localhost:8200/v1/sys/auth | jq -r '."okta/".accessor')

#Add the mount
cat <<EOM > okta_mfa.json
{
  "mount_accessor": "${OKTA_ACCESSOR}",
  "org_name": "${OKTA_ORG}",
  "api_token": "${OKTA_API_TOKEN}",
  "username_format": "{{alias.name}}",
  "base_url": "oktapreview.com",
  "bypass_okta_mfa" : true 
}
EOM


logger "Creating Sentinel policy enforcing Okta MFA login"
#Following policy is Base64 encoded below in policy block
: '
import "mfa"
import "strings"

# Require OKTA MFA validation to succeed
okta_valid = rule {
    #mfa.methods.okta.valid
    true
}

main = rule when strings.has_prefix(request.path, "auth/okta/login") {
    okta_valid
}
'

cat <<EOM > okta_sentinel.json
{
  "policy": "aW1wb3J0ICJzdHJpbmdzIg0KaW1wb3J0ICJtZmEiDQoNCiMgUmVxdWlyZSBPS1RBIE1GQSB2YWxpZGF0aW9uIHRvIHN1Y2NlZWQNCm9rdGFfdmFsaWQgPSBydWxlIHsNCiAgICBtZmEubWV0aG9kcy5va3RhLnZhbGlkDQp9DQoNCm1haW4gPSBydWxlIHdoZW4gc3RyaW5ncy5oYXNfcHJlZml4KHJlcXVlc3QucGF0aCwgImF1dGgvb2t0YS9sb2dpbiIpIHsNCiAgICBva3RhX3ZhbGlkDQp9",
  "paths": ["auth/okta/login/*"],
  "enforcement_level": "hard-mandatory"
}
EOM

logger "Configure Okta MFA in Vault"
curl \
    --silent \
    --header "X-Vault-Token: password" \
    --request POST \
    --data @okta_mfa.json \
    http://localhost:8200/v1/sys/mfa/method/okta/okta

logger "Configuring Sentinel rule for Okta MFA login"
curl  \
    --silent \
    --header "X-Vault-Token: password" \
    --request PUT \
    --data @okta_sentinel.json \
    http://localhost:8200/v1/sys/policies/egp/okta
