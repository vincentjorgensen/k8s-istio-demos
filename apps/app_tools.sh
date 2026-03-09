#!/usr/bin/env bash
function app_init_utils {
  if $UTILS_ENABLED; then
    echo '# '"$0"
    $ITER_MC exec_utils
  fi
}

function app_init_netshoot {
  if $NETSHOOT_ENABLED; then
    echo '# '"$0"
    $ITER_MC exec_netshoot
  fi
}

function app_init_curl {
  if $CURL_ENABLED; then
    echo '# '"$0"
    $ITER_MC exec_curl
  fi
}

function exec_utils {
  local _manifest="$MANIFESTS/tools.utils.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/tools/utils.manifest.yaml.j2

  _label_ns_for_istio "$UTILS_NAMESPACE"

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
  _wait_for_pods "$GSI_CONTEXT" "$UTILS_NAMESPACE" utils
}

function exec_netshoot {
  local _manifest="$MANIFESTS/tools.netshoot.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/tools/netshoot.manifest.yaml.j2

  _label_ns_for_istio "$NETSHOOT_NAMESPACE"
  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
  _wait_for_pods "$GSI_CONTEXT" "$NETSHOOT_NAMESPACE" netshoot
}


function exec_curl {
  local _manifest="$MANIFESTS/tools.curl.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/tools/curl.manifest.yaml.j2

  _label_ns_for_istio "$CURL_NAMESPACE"
  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
  _wait_for_pods "$GSI_CONTEXT" "$CURL_NAMESPACE" curl
}
