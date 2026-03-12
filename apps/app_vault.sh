#!/usr/bin/env bash
# https://dev.to/rajesh_kumar_36a2b4761e0d/how-to-set-up-hashicorp-vault-on-kubernetes-96d

function app_init_vault {
  if $VAULT_ENABLED; then
    echo '# '"$0"
    exec_vault
  fi
}

function exec_vault {
  local _manifest="$MANIFESTS/helm.vault.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/helm.vault.yaml.j2

  if is_create_mode; then
    _make_manifest "$_template" > "$_manifest"

    $DRY_RUN helm upgrade --install vault hashicorp/vault                      \
    --version "${VAULT_VER}"                                                   \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$VAULT_NAMESPACE"                                             \
    --create-namespace                                                         \
    --values "$_manifest"                                                      \
    --wait

    _wait_for_pods_running "$KSA_CONTEXT" "$VAULT_NAMESPACE" "vault"

    exec_vault_initialize
    exec_vault_unseal
    exec_vault_login
    exec_vault_enable_secrets_engine
  else
    $DRY_RUN helm uninstall vault                                              \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$VAULT_NAMESPACE"
  fi
}

function exec_vault_initialize {
  local _vault_keys="$MANIFESTS/vault.keys.${KSA_CLUSTER}.yaml"

  if is_create_mode; then
    $DRY_RUN kubectl exec vault-0                                              \
    --context "$KSA_CONTEXT"                                                   \
    --namespace "$VAULT_NAMESPACE"                                             \
    --stdin=false                                                              \
    --tty=false                                                                \
    -- vault operator init                                                     \
    > "$_vault_keys" 2>&1

    echo "_vault_keys=$_vault_keys"
  fi
}

function exec_vault_unseal {
  local _vault_keys="$MANIFESTS/vault.keys.${KSA_CLUSTER}.yaml"
  local _key1 _key2 _key3

  _key1=$(grep 'Unseal Key 1' "$_vault_keys" | awk -F': ' '{print $2}')
  _key2=$(grep 'Unseal Key 2' "$_vault_keys" | awk -F': ' '{print $2}')
  _key3=$(grep 'Unseal Key 3' "$_vault_keys" | awk -F': ' '{print $2}')
  
  if is_create_mode; then
    for key in "$_key1" "$_key2" "$_key3"; do
      $DRY_RUN kubectl exec vault-0                                            \
      --context "$KSA_CONTEXT"                                                 \
      --namespace "$VAULT_NAMESPACE"                                           \
      --stdin=false                                                            \
      --tty=false                                                              \
      -- vault operator unseal "$key"
    done

    _wait_for_pods "$KSA_CONTEXT" "$VAULT_NAMESPACE" "vault"
  fi
}

function exec_vault_login {
  local _vault_keys="$MANIFESTS/vault.keys.${KSA_CLUSTER}.yaml"
  local _root_token

  _root_token=$(grep 'Initial Root Token' "$_vault_keys" | awk -F': ' '{print $2}')

  if is_create_mode; then
    $DRY_RUN kubectl exec vault-0                                              \
    --context "$KSA_CONTEXT"                                                   \
    --namespace "$VAULT_NAMESPACE"                                             \
    --stdin=false                                                              \
    --tty=false                                                                \
    -- vault login "$_root_token"
  fi
}

function exec_vault_enable_secrets_engine {
  if is_create_mode; then
    $DRY_RUN kubectl exec vault-0                                              \
    --context "$KSA_CONTEXT"                                                   \
    --namespace "$VAULT_NAMESPACE"                                             \
    --stdin=false                                                              \
    --tty=false                                                                \
    -- vault secrets enable --version=2 --path=kv kv
  fi
}
