#!/usr/bin/env bash
function app_init_gloo_gateway_v2 {
  if $GLOO_GATEWAY_V2_ENABLED; then
    $ITER_MC_1 exec_gloo_gateway_v2_crds
    $ITER_MC_1 exec_gloo_gateway_v2_control_plane
  fi
}

function exec_gloo_gateway_v2_crds {
  local _manifest="$MANIFESTS/helm.gloo-gateway-v2-crds.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gloo-gateway-v2/helm.crds.yaml.j2

  _make_manifest "$_template" > "$_manifest"

  if is_create_mode; then
    $DRY_RUN helm upgrade --install                                            \
             gloo-gateway-crds "$GLOO_GATEWAY_V2_HELM_REPO/gloo-gateway-crds"  \
    --version "$GLOO_GATEWAY_V2_VER"                                           \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$GLOO_GATEWAY_NAMESPACE"                                      \
    --create-namespace                                                         \
    --values "$_manifest"                                                      \
    --wait
  else 
    $DRY_RUN helm uninstall gloo-gateway-crds                                  \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$GLOO_GATEWAY_NAMESPACE"
  fi
}

function exec_gloo_gateway_v2_control_plane {
  local _manifest="$MANIFESTS/helm.gloo-gateway-v2.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gloo-gateway-v2/helm.values.yaml.j2

  _make_manifest "$_template" > "$_manifest"

  if is_create_mode; then
    $DRY_RUN helm upgrade --install                                            \
             gloo-gateway "$GLOO_GATEWAY_V2_HELM_REPO/gloo-gateway"            \
    --version "$GLOO_GATEWAY_V2_VER"                                           \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$GLOO_GATEWAY_NAMESPACE"                                      \
    --values "$_manifest"                                                      \
    --wait
  else 
    $DRY_RUN helm uninstall gloo-gateway                                       \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$GLOO_GATEWAY_NAMESPACE"
  fi

  if is_create_mode; then
    $DRY_RUN kubectl wait                                                      \
    --context="$GSI_CONTEXT"                                                   \
    --namespace "$GLOO_GATEWAY_NAMESPACE"                                      \
    --for=condition=Ready pods --all
  fi
}

function exec_backend {
  local _manifest="$MANIFESTS/backend.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gloo-gateway-v2/backend.manifest.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$GSI_CLUSTER".yaml

  jinja2                                                                       \
         -D service_name="$GSI_APP_SERVICE_NAME"                               \
         -D service_namespace="$GSI_APP_SERVICE_NAMESPACE"                     \
         -D service_port="$GSI_APP_SERVICE_PORT"                               \
         "$_template"                                                          \
         "$_j2"                                                               \
  > "$_manifest"

  _apply_manifest "$_manifest"
}

function exec_reference_grant {
  local _manifest="$MANIFESTS/gloo-gateway-v2.reference_grant.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gloo-gateway-v2/reference_grant.manifest.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$GSI_CLUSTER".yaml

  jinja2                                                                       \
         -D gateway_namespace="$INGRESS_NAMESPACE"                             \
         -D service="$GSI_APP_SERVICE_NAME"                                    \
         -D service_namespace="$GSI_APP_SERVICE_NAMESPACE"                     \
         -D multicluster="$MC_FLAG"                                            \
         "$_template"                                                          \
         "$_j2"                                                               \
  > "$_manifest"

  _apply_manifest "$_manifest"
}

function create_reference_grant {

  while getopts "m:n:s:" opt; do
    # shellcheck disable=SC2220
    case $opt in
      m)
        _service_name=$OPTARG ;;
      n)
        _namespace=$OPTARG ;;
      s)
        _service_namespace=$OPTARG ;;
    esac
  done
  local _manifest="$MANIFESTS/gloo-gateway-v2.reference_grant.${_service_name}.${_service_namespace}.${GSI_CLUSTER}.yaml"
  local _j2="$MANIFESTS"/jinja2_globals."$GSI_CLUSTER".yaml

  jinja2                                                                       \
         -D gateway_namespace="$_namespace"                                    \
         -D service="$_service_name"                                           \
         -D service_namespace="$_service_namespace"                            \
         "$_template"                                                          \
         "$_j2"                                                               \
  > "$_manifest"

  _apply_manifest "$_manifest"
}

function exec_gloo_gateway_v2_keycloak_secret {
  create_keycloak_secret "$GLOO_GATEWAY_NAMESPACE"
}

function exec_extauth_keycloak_ggv2_auth_config {
  local _gateway_address
  local _manifest="$MANIFESTS/gloo-gateway-v2.auth_config.oauth.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gloo-gateway-v2/auth_config.oauth.manifest.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$GSI_CLUSTER".yaml

  jinja2                                                                       \
         -D client_id="$KEYCLOAK_CLIENT"                                       \
         -D gateway_address="${GSI_APP_SERVICE_NAME}.${TLDN}"                  \
         -D httproute_name="${GSI_APP_SERVICE_NAME}-route"                     \
         -D httproute_namespace="${GSI_APP_SERVICE_NAMESPACE}-route"           \
         -D keycloak_url="$KEYCLOAK_URL"                                       \
         -D service_namespace="$GSI_APP_SERVICE_NAMESPACE"                     \
         -D system_namespace="$GLOO_GATEWAY_NAMESPACE"                         \
         "$_template"                                                          \
         "$_j2"                                                               \
  > "$_manifest"

  _apply_manifest "$_manifest"
}
