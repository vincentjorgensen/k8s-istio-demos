#!/usr/bin/env bash
function app_init_httpbin {
  if $HTTPBIN_ENABLED; then
    echo '# '"$0"
    $ITER_MC exec_httpbin
 fi
}

function exec_httpbin {
  local _manifest="$MANIFESTS/httpbin.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES/httpbin.manifest.yaml.j2"

  _label_ns_for_istio "$HTTPBIN_NAMESPACE"

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
  _wait_for_pods "$GSI_CONTEXT" "$HTTPBIN_NAMESPACE" httpbin
}

function exec_httpbin_routing {
  if $HTTPBIN_ENABLED; then
    if $GATEWAY_API_ENABLED; then
      create_httproute -m "$HTTPBIN_SERVICE_NAME"                              \
                       -n "$HTTPBIN_NAMESPACE"                                 \
                       -s "$HTTPBIN_NAMESPACE"                                 \
                       -p "$HTTPBIN_SERVICE_PORT"
    fi

    if $GLOO_EDGE_ENABLED; then
      create_gloo_edge_virtual_service                                         \
      -s "$HTTPBIN_SERVICE_NAME"                                               \
      -n "$HTTPBIN_NAMESPACE"                                                  \
      -p "$HTTPBIN_SERVICE_PORT"
    fi

    if $GME_ENABLED; then
      create_gloo_route_table                                                  \
        -w "$GME_APPLICATIONS_WORKSPACE"                                       \
        -s "$HTTPBIN_SERVICE_NAME"

      create_gloo_virtual_destination                                          \
        -w "$GME_APPLICATIONS_WORKSPACE"                                       \
        -s "$HTTPBIN_SERVICE_NAME"                                             \
        -p "$HTTPBIN_SERVICE_PORT"
    fi
  fi
}
