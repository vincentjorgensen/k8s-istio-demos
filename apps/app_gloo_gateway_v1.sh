function app_init_gloo_gateway_v1 {
  if $GLOO_GATEWAY_V1_ENABLED; then
    echo '# '"$0"
    $ITER_MC_1 exec_gloo_gateway_v1
  fi
}

function exec_gloo_gateway_v1 {
  local _manifest="$MANIFESTS/helm.gloo-gateway-v1.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gloo-gateway-v1/helm.values.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  jinja2                                                                       \
          -D gloo_gateway_license_key="$GLOO_GATEWAY_LICENSE_KEY"              \
         "$_template"                                                          \
         "$_j2"                                                               \
  > "$_manifest"

  if is_create_mode; then
    $DRY_RUN helm upgrade -i gloo-gateway glooe/gloo-ee                        \
    --version="$GLOO_GATEWAY_V1_VER"                                           \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace="$GLOO_GATEWAY_NAMESPACE"                                      \
    --values "$_manifest"                                                      \
    --wait
  else
    $DRY_RUN helm uninstall gloo-gateway                                       \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace="$GLOO_GATEWAY_NAMESPACE"
  fi
}

function exec_gloo_gateway_v1_gateway {
  local _manifest="$MANIFESTS/gloo-gateway-v1.gateway.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gloo-gateway-v1/gateway.manifest.yaml.j2

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
}
