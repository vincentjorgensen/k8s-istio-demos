#!/usr/bin/env bash
function app_init_gateway_api {
  if $GATEWAY_API_ENABLED; then 
    echo '# '"$0"
    $ITER_MC exec_gateway_api_crds 
  fi
}

function app_init_ingress_gateway_api {
  if $GATEWAY_API_ENABLED; then 
    echo '# '"$0"
    if $INGRESS_ENABLED; then
      if $KEYCLOAK_ENABLED; then
        if $KGATEWAY_ENABLED; then
          $ITER_MC_1 exec_kgateway_keycloak_secret
        elif $GLOO_GATEWAY_V2_ENABLED; then
          $ITER_MC_1 exec_gloo_gateway_v2_keycloak_secret
        fi
      fi
      $ITER_MC_1 exec_ingress_gateway_api
    fi
  fi
}

function app_init_eastwest_gateway_api {
  if $GATEWAY_API_ENABLED && $MULTICLUSTER_ENABLED; then
    echo '# '"$0"
    $ITER_MC exec_eastwest_gateway_api

    $ITER_MC exec_eastwest_link_gateway_api
  fi
}

function exec_gateway_api_crds {
  local _gateway_api_ver
  if ! kubectl --context "$KSA_CONTEXT" get crds|grep -q gateways.gateway.networking.k8s.io; then
    # Install either experimental or standard
    if $GATEWAY_API_ENABLED && $GATEWAY_API_EXP_CRDS_ENABLED; then
      exec_gateway_api_experimental_crds
    elif $GATEWAY_API_ENABLED; then
      exec_gateway_api_standard_crds
    fi
  else
    _gateway_api_ver=$(
      kubectl get crd gateways.gateway.networking.k8s.io                       \
        --context "$KSA_CONTEXT" -ojson                                       |\
      jq -r '.metadata.annotations | ."gateway.networking.k8s.io/bundle-version" , ."gateway.networking.k8s.io/channel"' |\
      tr '\n' ' '                                                             |\
      sed -e 's/ /-/'
    )
    echo '#'" Kubernetes Gateway API Version ${_gateway_api_ver} already installed"
  fi
}

function exec_gateway_api_standard_crds {
  if is_create_mode; then
    $DRY_RUN kubectl "$KSA_MODE"                                               \
    --context "$KSA_CONTEXT"                                                   \
    -f "$GATEWWAY_API_CRDS_URL"/"$GATEWAY_API_VER"/standard-install.yaml
  fi

  if ! is_create_mode; then
    $DRY_RUN kubectl "$KSA_MODE"                                               \
    --context "$KSA_CONTEXT"                                                   \
    -f "$GATEWWAY_API_CRDS_URL"/"$GATEWAY_API_VER"/standard-install.yaml
  fi
}

function exec_gateway_api_experimental_crds {
  if is_create_mode; then
    $DRY_RUN kubectl apply                                                   \
    --context "$KSA_CONTEXT"                                                 \
    --server-side=true                                                       \
    -f "$GATEWWAY_API_CRDS_URL"/"$GATEWAY_API_EXP_VER"/experimental-install.yaml
  fi

  if ! is_create_mode; then
    $DRY_RUN kubectl "$KSA_MODE"                                               \
    --context "$KSA_CONTEXT"                                                   \
    -f "$GATEWWAY_API_CRDS_URL"/"$GATEWAY_API_EXP_VER"/experimental-install.yaml
  fi
}

function exec_httproute {
  local _manifest="$MANIFESTS/gateway-api.httproute.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gateway-api/httproute.manifest.yaml.j2

  jinja2                                                                       \
         -D namespace="$INGRESS_NAMESPACE"                                     \
         -D service="$KSA_APP_SERVICE_NAME"                                    \
         -D service_namespace="$KSA_APP_SERVICE_NAMESPACE"                     \
         -D service_port="$KSA_APP_SERVICE_PORT"                               \
         "$_template"                                                          \
         "$(_get_j2)"                                                          \
  > "$_manifest"

  _apply_manifest "$_manifest"
}

function create_httproute {
  local _service_name _service_port _namespace
  while getopts "m:n:p:s:" opt; do
    # shellcheck disable=SC2220
    case $opt in
      m)
        _service_name=$OPTARG ;;
      s)
        _service_namespace=$OPTARG ;;
      n)
        _namespace=$OPTARG ;;
      p)
        _service_port=$OPTARG ;;
    esac
  done

  local _manifest="$MANIFESTS/gateway-api.httproute.${_service_name}.${_namespace}.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gateway-api/httproute.manifest.yaml.j2

  jinja2                                                                       \
         -D namespace="$_namespace"                                            \
         -D service="$_service_name"                                           \
         -D service_namespace="$_service_namespace"                            \
         -D service_port="$_service_port"                                      \
         "$_template"                                                          \
         "$(_get_j2)"                                                          \
  > "$_manifest"

  _apply_manifest "$_manifest"

  # create_reference_grant
  if [[ $_service_namespace != "$_namespace" ]]; then
    create_reference_grant -m "$_service_name" -s "$_service_namespace" -n "$_namespace"
  fi
}

function exec_eastwest_gateway_api {
  local _ew_manifest="$MANIFESTS/gateway-api.eastwest_gateway.${KSA_CLUSTER}.yaml"
  local _ew_template="$TEMPLATES"/gateway-api/eastwest_gateway.gateway.manifest.yaml.j2
  local _pa_manifest="$MANIFESTS/gateway-api.eastwest_parameters.${KSA_CLUSTER}.yaml"
  local _pa_template="$TEMPLATES"/gateway-api/eastwest_parameters.gateway.manifest.yaml.j2

  _make_manifest "$_pa_template" > "$_pa_manifest"
  _make_manifest "$_ew_template" > "$_ew_manifest"

  _apply_manifest "$_pa_manifest"
  _apply_manifest "$_ew_manifest"

  _wait_for_pods "$KSA_CONTEXT" "$EASTWEST_NAMESPACE" "$EASTWEST_GATEWAY"
}

function exec_eastwest_link_gateway_api {
  local _manifest _j2
  local _template="$TEMPLATES"/gateway-api/eastwest_remote_gateway.manifest.yaml.j2
  local _remote_address _address_type

  for cluster in $(env|ggrep KSA_CLUSTER|sed -e 's/KSA_CLUSTER\(.*\)=.*/\1/'); do
    if ! [[ "$KSA_CLUSTER" == "$(eval echo '$'KSA_CLUSTER"${cluster}")" ]]; then
     
      _remote_address=$(
        $DRY_RUN kubectl get svc "$EASTWEST_GATEWAY"                           \
        --namespace "$EASTWEST_NAMESPACE"                                      \
        --context "$(eval echo '$'KSA_CONTEXT"${cluster}")"                    \
        -o jsonpath="{.status.loadBalancer.ingress[0]['hostname','ip']}")

      if is_create_mode; then
      while [[ -z $_remote_address ]]; do
          _remote_address=$(
            $DRY_RUN kubectl get svc "$EASTWEST_GATEWAY"                       \
            --namespace "$EASTWEST_NAMESPACE"                                  \
            --context "$(eval echo '$'KSA_CONTEXT"${cluster}")"                \
            -o jsonpath="{.status.loadBalancer.ingress[0]['hostname','ip']}")
          echo -n '.' && sleep 5
        done && echo
        fi

      if echo "$_remote_address" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        _address_type=IPAddress
      else
        _address_type=Hostname
      fi
  
      _j2="$MANIFESTS"/jinja2_globals."$(eval echo '$'KSA_CLUSTER"${cluster}")".yaml
      _manifest="$MANIFESTS/gateway_api.eastwest_remote_gateway.remote-$(eval echo '$'KSA_CONTEXT"${cluster}").${KSA_CLUSTER}.yaml"
      jinja2                                                                   \
             -D address_type="$_address_type"                                  \
             -D remote_address="$_remote_address"                              \
             -D trust_domain="$TRUST_DOMAIN"                                   \
             "$_template"                                                      \
             "$_j2"                                                            \
      > "$_manifest"
    
      _apply_manifest "$_manifest"
    fi
  done
}

function exec_ingress_gateway_api {
  local _in_manifest="$MANIFESTS/gateway-api.ingress_gateway.${KSA_CLUSTER}.yaml"
  local _in_template="$TEMPLATES"/gateway-api/ingress_gateway.gateway.manifest.yaml.j2
  local _pa_manifest="$MANIFESTS/gateway-api.ingress_parameters.${KSA_CLUSTER}.yaml"
  local _pa_template="$TEMPLATES"/gateway-api/ingress_parameters.gateway.manifest.yaml.j2
  local _te_manifest="$MANIFESTS/gateway-api.telemetry.${KSA_CLUSTER}.yaml"
  local _te_template="$TEMPLATES"/gateway-api/telemetry.gateway.manifest.yaml.j2

  _label_ns_for_istio "$INGRESS_NAMESPACE"

  _make_manifest "$_pa_template" > "$_pa_manifest"
  _make_manifest "$_in_template" > "$_in_manifest"
  _make_manifest "$_te_template" > "$_te_manifest"

  $DRY_RUN kubectl "$KSA_MODE"                                                 \
  --context "$KSA_CONTEXT"                                                     \
  -f "$_pa_manifest"

  $DRY_RUN kubectl "$KSA_MODE"                                                 \
  --context "$KSA_CONTEXT"                                                     \
  -f "$_in_manifest"

  $DRY_RUN kubectl "$KSA_MODE"                                                 \
  --context "$KSA_CONTEXT"                                                     \
  -f "$_te_manifest"
}
