#!/usr/bin/env bash
function app_init_namespaces {
  $ITER_MC exec_namespaces

  if $GME_ENABLED; then
    echo '#' "GME is enabled, creating namespace $GME__NAMESPACE on mgmt server $KSA_MGMT_CLUSTER"
    create_namespace "$KSA_MGMT_CONTEXT" "$GME_NAMESPACE"
  fi
}

function exec_namespaces {
  for enabled_var in $(env|grep _ENABLED); do
    enabled=$(echo "$enabled_var" | awk -F= '{print $1}')
    if eval '$'"${enabled}"; then
      # shellcheck disable=SC2116
      if [[ -n "$(eval echo '$'"$(echo "${enabled%%_ENABLED}_NAMESPACE")")" ]]; then
        echo '#' "${enabled%%_ENABLED} is enabled, creating namespace $(eval echo '$'"${enabled%%_ENABLED}_NAMESPACE")"
        create_namespace "$KSA_CONTEXT" "$(eval echo '$'"$(echo "${enabled%%_ENABLED}_NAMESPACE")")"
      fi
    fi
  done
}

function create_namespace {
  local _context _namespace
  _context=$1
  _namespace=$2

  if ! _namespace_exists "$_context" "$_namespace"; then
    $DRY_RUN kubectl "${KSA_MODE/apply/create}" namespace "$_namespace"          \
    --context "$_context"
  fi
}

function _namespace_exists {
  local _context=$1
  local _namespace=$2

  kubectl get namespace "$_namespace" --context "$_context" > /dev/null 2>&1
}
