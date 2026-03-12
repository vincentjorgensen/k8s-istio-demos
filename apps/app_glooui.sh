#!/usr/bin/env bash
function app_init_glooui {
  if $GLOOUI_ENABLED; then
    echo '# '"$0"
    exec_glooui_gloo_platform_crds
    exec_glooui_gloo_platform
    exec_istio_base

  fi
}

function exec_glooui_gloo_platform_crds {
  if is_create_mode; then
    $DRY_RUN helm upgrade -i gloo-platform-crds                                \
                             gloo-platform/gloo-platform-crds                  \
    --version="$GME_VER"                                                       \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace="$GLOO_SYSTEM_NAMESPACE"                                       \
    --create-namespace                                                         \
    --set installEnterpriseCrds=false                                          \
    --wait
  else
    $DRY_RUN helm uninstall gloo-platform-crds                                 \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace="$GLOO_SYSTEM_NAMESPACE"
  fi
}

function exec_glooui_gloo_platform {
  local _manifest="$MANIFESTS/helm.gloo-platform.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/helm.gloo-platform.yaml.j2

  if is_create_mode; then
    _make_manifest "$_template" > "$_manifest"

    $DRY_RUN helm upgrade -i gloo-platform gloo-platform/gloo-platform         \
    --version="$GME_VER"                                                       \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace="$GLOO_SYSTEM_NAMESPACE"                                       \
    --values "$_manifest"                                                      \
    --wait
  else
    $DRY_RUN helm uninstall gloo-platform                                      \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace="$GLOO_SYSTEM_NAMESPACE"
  fi

  _wait_for_pods "$KSA_CONTEXT" "$GLOO_SYSTEM_NAMESPACE" gloo-mesh-ui
}
