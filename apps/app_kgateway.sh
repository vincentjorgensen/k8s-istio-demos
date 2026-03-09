#!/usr/bin/env bash
function app_init_kgateway {
  if $KGATEWAY_ENABLED; then
    echo '# '"$0"
    exec_kgateway_crds
    exec_kgateway_control_plane
  
    if $MULTICLUSTER_ENABLED; then
      gsi_cluster_swap
      exec_kgateway_crds
      exec_kgateway_control_plane
      gsi_cluster_swap
    fi
  fi
}

function exec_kgateway_crds {
  if is_create_mode; then
    # shellcheck disable=SC2086
    $DRY_RUN helm upgrade --install kgateway-crds "$KGATEWAY_CRDS_HELM_REPO"   \
    --version "$KGATEWAY_HELM_VER"                                             \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$KGATEWAY_SYSTEM_NAMESPACE"                                   \
    --wait
  else
    $DRY_RUN helm uninstall kgateway-crds                                      \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$KGATEWAY_SYSTEM_NAMESPACE"
  fi
}

function exec_kgateway_control_plane {
  local _k_label="=ambient"

  if ! is_create_mode; then
    _k_label="-"
  fi

  if $AMBIENT_ENABLED; then
    $DRY_RUN kubectl label namespace "$INGRESS_NAMESPACE" "istio.io/dataplane-mode${_k_label}"  \
    --context "$GSI_CONTEXT" --overwrite
  fi

  if is_create_mode; then
    # shellcheck disable=SC2086
    $DRY_RUN helm upgrade --install kgateway "$KGATEWAY_HELM_REPO"             \
    --version "$KGATEWAY_HELM_VER"                                             \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$KGATEWAY_SYSTEM_NAMESPACE"                                   \
    --wait
  else
    $DRY_RUN helm uninstall kgateway                                           \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$KGATEWAY_SYSTEM_NAMESPACE"
  fi

  if is_create_mode; then
    $DRY_RUN kubectl wait                                                      \
    --context="$GSI_CONTEXT"                                                   \
    --namespace "$KGATEWAY_SYSTEM_NAMESPACE"                                   \
    --for=condition=Ready pods --all
  fi
}

function exec_kgateway_keycloak_secret {
  create_keycloak_secret "$KGATEWAY_SYSTEM_NAMESPACE"
}

