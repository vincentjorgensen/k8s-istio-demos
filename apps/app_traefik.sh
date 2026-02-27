#!/usr/bin/env bash
function app_init_traefik {
  if $TRAEFIK_ENABLED; then
    $ITER_MC_1 exec_traefik_rbac
    $ITER_MC_1 exec_traefik
  fi
}

function exec_traefik {
  local _manifest="$MANIFESTS/helm.traefik.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/traefik/helm.traefik.yaml.j2

  _make_manifest "$_template" > "$_manifest"

  if is_create_mode; then
    $DRY_RUN helm upgrade --install                                            \
             traefik "$TRAEFIK_HELM_REPO/traefik"                              \
    --version "$TRAEFIK_VER"                                                   \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$TRAEFIK_NAMESPACE"                                           \
    --create-namespace                                                         \
    --values "$_manifest"                                                      \
    --wait
  else 
    $DRY_RUN helm uninstall traefik                                            \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$TRAEFIK_NAMESPACE"
  fi
}

function exec_traefik_rbac {
  # https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/
  # Install Traefik RBACs.
  local _traefik_app_ver _tav _rbac_url
  _traefik_app_ver=$(helm search repo traefik --versions                      |\
                     grep traefik/traefik                                     |\
                     grep "$TRAEFIK_VER"                                      |\
                     awk '{print $3}')
  _tav=${_traefik_app_ver%.*}
  _rbac_url=https://raw.githubusercontent.com/traefik/traefik
  _rbac_url="$_rbac_url"/"$_tav"
  _rbac_url="$_rbac_url"/docs/content/reference
  _rbac_url="$_rbac_url"/dynamic-configuration/kubernetes-gateway-rbac.yml
  if is_create_mode; then
    kubectl apply -f "$_rbac_url"
  else
    kubectl delete -f "$_rbac_url"
  fi
}
