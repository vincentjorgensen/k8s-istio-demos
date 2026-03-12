#!/usr/bin/env bash
function app_init_helloworld {
  if $HELLOWORLD_ENABLED; then
    echo '# '"$0"
    $ITER_MC exec_helloworld
  fi

  if $REMOTE_HELLOWORLD_ENABLED; then
    echo '# '"$0"
    $ITER_MC exec_remote_helloworld
  fi
}

function exec_helloworld {
  local _manifest="$MANIFESTS/helloworld.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/helloworld.manifest.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  _label_ns_for_istio "$HELLOWORLD_NAMESPACE"

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"

  _wait_for_pods "$KSA_CONTEXT" "$HELLOWORLD_NAMESPACE" helloworld
}

function exec_remote_helloworld {
  local _manifest="$MANIFESTS/remote-helloworld.backend.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/gateway-api/remote-hellowworld.backend.manifest.yaml.j2

  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  _remote_helloworld_address=$(docker inspect helloworld | jq -r '.[].NetworkSettings.Networks."'"$DOCKER_NETWORK"'".IPAddress')
  _remote_helloworld_port=$(docker inspect helloworld | jq -r '.[].Config.Env[]|select(contains("SERVER_PORT"))'|awk -F= '{print $2}')
  _remote_helloworld_ssl_port=$(docker inspect helloworld | jq -r '.[].Config.Env[]|select(contains("SERVER_SSL_PORT"))'|awk -F= '{print $2}')

  jinja2                                                                       \
         -D remote_helloworld_address="${_remote_helloworld_address}"          \
         -D remote_helloworld_port="${_remote_helloworld_port}"                \
         -D remote_helloworld_ssl_port="${_remote_helloworld_ssl_port}"        \
         "$_template"                                                          \
         "$_j2"                                                                \
    > "$_manifest"

  _apply_manifest "$_manifest"
}

function exec_helloworld_routing {
  if $HELLOWORLD_ENABLED; then
    if $EXTAUTH_ENABLED; then
      create_keycloak_extauth_auth_config -m "$HELLOWORLD_SERVICE_NAME"        \
                                          -s "$HELLOWORLD_NAMESPACE"           \
                                          -h "$HELLOWORLD_NAMESPACE"           \
                                          -n "$HELLOWORLD_NAMESPACE"           \
                                          -p "$HELLOWORLD_SERVICE_PORT"

    fi

    if $GATEWAY_API_ENABLED; then
      create_httproute -m "$HELLOWORLD_SERVICE_NAME"                           \
                       -n "$HELLOWORLD_NAMESPACE"                              \
                       -s "$HELLOWORLD_NAMESPACE"                              \
                       -p "$HELLOWORLD_SERVICE_PORT"
    fi

    if $GLOO_EDGE_ENABLED; then
      create_gloo_edge_virtual_service                                         \
      -s "$HELLOWORLD_SERVICE_NAME"                                            \
      -n "$HELLOWORLD_NAMESPACE"                                               \
      -p "$HELLOWORLD_SERVICE_PORT"
    fi

    if $GME_ENABLED; then
      create_gloo_route_table                                                  \
        -w "$GME_APPLICATIONS_WORKSPACE"                                       \
        -s "$HELLOWORLD_SERVICE_NAME"

      create_gloo_virtual_destination                                          \
        -w "$GME_APPLICATIONS_WORKSPACE"                                       \
        -s "$HELLOWORLD_SERVICE_NAME"                                          \
        -p "$HELLOWORLD_SERVICE_PORT"
    fi
  fi

  if $REMOTE_HELLOWORLD_ENABLED; then
    if $GATEWAY_API_ENABLED; then
      local _manifest="$MANIFESTS/httproute.remote-helloworld.${KSA_CLUSTER}.yaml"
      local _template="$TEMPLATES"/gateway-api/httproute.remote-helloworld.manifest.yaml.j2
      
      _make_manifest "$_template" > "$_manifest"
      _apply_manifest "$_manifest"
    fi
  fi
}
