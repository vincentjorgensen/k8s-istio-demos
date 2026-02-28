function app_init_ingress {
  if $INGRESS_ENABLED; then
    $ITER_MC_1 exec_enmesh_ingress_namespace
  fi
}

function exec_enmesh_ingress_namespace {
  local _k_label="=ambient"

  if ! is_create_mode; then
    _k_label="-"
  fi

  if $AMBIENT_ENABLED; then
    $DRY_RUN kubectl label namespace "$INGRESS_NAMESPACE"                      \
    "istio.io/dataplane-mode${_k_label}"                                       \
    --context "$GSI_CONTEXT" --overwrite
  fi
}
