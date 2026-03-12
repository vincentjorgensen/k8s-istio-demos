#!/usr/bin/env bash
function app_init_cilium {
  if $CILIUM_ENABLED; then
    $ITER_MC exec_cilium
  fi
}

function exec_cilium {
  local _manifest="$MANIFESTS/helm.cilium.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES/helm.cilium.yaml.j2"
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  local _k8s_svc_host _k8s_svc_port
  _k8s_svc_host=$(
      kubectl config view                                                     |\
      yq '.clusters[] | select (.name == "k3d-cluster1")|.cluster.server'     |\
      sed -e 's;https://\(.*\);\1;'
  )

  if [[ $_k8s_svc_host =~ : ]]; then
    _k8s_svc_port=$(echo "$_k8s_svc_host" | awk -F: '{print $2}')
    _k8s_svc_host=$(echo "$_k8s_svc_host" | awk -F: '{print $1}')
  else
    _k8s_svc_port=443
  fi

  if [[ $_k8s_svc_host == 0.0.0.0 ]]; then
    _k8s_svc_host=localhost
  fi

  jinja2 -D k8s_svc_host="$_k8s_svc_host"                                      \
         -D k8s_svc_port="$_k8s_svc_port"                                      \
       "$_template"                                                            \
       "$_j2"                                                                  \
    > "$_manifest"
  
  if is_create_mode; then
    $DRY_RUN helm upgrade -i cilium cilium/cilium                              \
    --version "$CILIUM_VER"                                                    \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$KUBE_SYSTEM_NAMESPACE"                                       \
    --values "$_manifest"                                                      \
    --wait
  else
    $DRY_RUN helm uninstall cilium                                             \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$KUBE_SYSTEM_NAMESPACE"                                       \
    --wait
  fi
}
