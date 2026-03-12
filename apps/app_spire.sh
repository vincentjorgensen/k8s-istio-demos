#!/usr/bin/env bash
function app_init_spire {
  if $SPIRE_ENABLED; then
    echo '# '"$0"
    exec_spire_secrets
    exec_spire_crds
    exec_spire_server
    
    if $MULTICLUSTER_ENABLED; then
      gsi_cluster_swap

      exec_spire_secrets
      exec_spire_crds
      exec_spire_server

      exec_exchange_bundles

      gsi_cluster_swap

      exec_exchange_bundles
    fi
  fi
}

### https://github.com/vchaudh3/istio-multi-cluster-federation/blob/main/spire/install-spire.sh

function exec_spire_secrets {
  if is_create_mode; then
    $DRY_RUN kubectl create secret generic "$SPIRE_SECRET"                     \
    --context "$KSA_CONTEXT"                                                   \
    --namespace "$SPIRE_NAMESPACE"                                             \
    --from-file=tls.crt="$SPIRE_CERTS"/root-cert.pem                           \
    --from-file=tls.key="$SPIRE_CERTS"/root-key.pem
  else
    $DRY_RUN kubectl "$KSA_MODE" secret "$SPIRE_SECRET"                        \
    --context "$KSA_CONTEXT"                                                   \
    --namespace "$SPIRE_NAMESPACE"
  fi
}

function exec_spire_crds {
  if is_create_mode; then
    # shellcheck disable=SC2086
    $DRY_RUN helm upgrade --install spire-crds spire/spire-crds                \
    --version "$SPIRE_CRDS_VER"                                                \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$SPIRE_NAMESPACE"                                             \
    --wait
  else
    $DRY_RUN helm uninstall spire-crds                                         \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$SPIRE_NAMESPACE"
  fi
}

function exec_spire_server {
  local _cid_manifest="$MANIFESTS"/spire.cluster-id."$KSA_CLUSTER".yaml
  local _cid_template="$TEMPLATES"/spire/cluster-id.manifest.yaml
  local _manifest="$MANIFESTS/helm.spire-server.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/spire/helm.server.yaml.j2
  local _cm_manifest="$MANIFESTS/spire.configmap.server.${KSA_CLUSTER}.yaml"
  local _cm_template="$TEMPLATES"/spire/configmap.server.manifest.yaml.j2
  local _kustomize_renderer="$MANIFESTS/spire-${KSA_CLUSTER}/kustomize.sh"
  local _kustomize="$MANIFESTS/spire-${KSA_CLUSTER}/kustomization.yaml"
  local _kustomize_template="$TEMPLATES"/spire/kustomization.yaml.j2
#  local _fed_patch_manifest="$MANIFESTS/spire-${KSA_CLUSTER}/spire-federation-patch.yaml"
#  local _fed_patch_template="$TEMPLATES"/spire/spire-federation-patch.yaml.j2
  local _post_renderer=""
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  if is_create_mode; then
    _make_manifest "$_template" > "$_manifest"

    if $MULTICLUSTER_ENABLED; then
      [[ ! -e $(dirname "$_kustomize_renderer") ]] && mkdir "$(dirname "$_kustomize_renderer")"

      jinja2 -D trust_domain="$TRUST_DOMAIN"                                   \
             -D remote_trust_domain="$REMOTE_TRUST_DOMAIN"                     \
             -D cluster="$KSA_CLUSTER"                                         \
             -D remote_cluster="$KSA_REMOTE_CLUSTER"                           \
             -D ca_country="US"                                                \
             -D ca_ou="Customer Success"                                       \
         "$_cm_template"                                                       \
         "$_j2"                                                                \
      > "$_cm_manifest"

    _make_manifest "$_kustomize_template" > "$_kustomize"

##      jinja2 -D spire_namespace="$SPIRE_NAMESPACE"                           \
##             "$_fed_patch_template"                                          \
##        > "$_fed_patch_manifest"

      cp "$TEMPLATES"/kustomize.sh "$_kustomize_renderer"
      _post_renderer="--post-renderer $_kustomize_renderer"
    fi

    # shellcheck disable=SC2086 disable=SC2046
    $DRY_RUN helm upgrade --install spire spire/spire                          \
    --version "$SPIRE_SERVER_VER"                                              \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$SPIRE_NAMESPACE"                                             \
    --values "$_manifest"                                                      \
    $(eval echo $_post_renderer)                                               \
    --wait

    $DRY_RUN kubectl wait                                                      \
    --namespace "$SPIRE_NAMESPACE"                                             \
    --for=condition=Ready pods --all
  else
    $DRY_RUN helm uninstall spire                                             \
    --kube-context="$KSA_CONTEXT"                                             \
    --namespace "$SPIRE_NAMESPACE"
  fi

  cp "$_cid_template"                                                         \
     "$_cid_manifest"

###  $DRY_RUN kubectl "$KSA_MODE"                                                \
###  --context "$KSA_CONTEXT"                                                    \
###  -f "$MANIFESTS"/spire.cluster-id."$KSA_CLUSTER".yaml
###
###  if $MULTICLUSTER_ENABLED && is_create_mode; then
###    $DRY_RUN kubectl get svc spire-server                                     \
###    --context "$KSA_CONTEXT"                                                  \
###    --namespace "$SPIRE_NAMESPACE"                                            \
###    -o jsonpath="{.status.loadBalancer.ingress[0]['hostname','ip']}"          \
###    > "$MANIFESTS"/spire-server.address
###
###    $DRY_RUN kubectl get svc spire-server                                     \
###    --context "$KSA_CONTEXT"                                                  \
###    --namespace "$SPIRE_NAMESPACE"                                            \
###    -o jsonpath="{.spec.ports[0].port}"                                       \
###    > "$MANIFESTS"/spire-server.port
###
###    kubectl get configmap spire-bundle                                        \
###    --context "$KSA_CONTEXT"                                                  \
###    --namespace "$SPIRE_NAMESPACE"                                            \
###    -o json                                                                  |\
###    jq -r '.data."bundle.spiffe"' > "$MANIFESTS"/spire-server.bundle 
###  fi
}

function exec_spire_agent {
  local _cid_manifest="$MANIFESTS"/spire.cluster-id."$KSA_CLUSTER".yaml
  local _cid_template="$TEMPLATES"/spire/cluster-id.manifest.yaml
  local _manifest="$MANIFESTS/helm.spire-agent.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/spire/helm.agent.yaml.j2
  local _spire_bundle="$MANIFESTS/configmap.spire-bundle.${KSA_CLUSTER}.yaml"
  local _bundle_template="$TEMPLATES"/spire/configmap.bundle.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

    jinja2 -D spire_bundle="$(cat "$MANIFESTS"/spire-server.bundle)"          \
         "$_bundle_template"                                                  \
         "$_j2"                                                               \
      > "$_spire_bundle"

    jinja2 -D trust_domain="$TRUST_DOMAIN"                                    \
           -D cluster="$KSA_CLUSTER"                                          \
           -D spire_server_address="$(cat "$MANIFESTS"/spire-server.address)" \
           -D spire_server_port="$(cat "$MANIFESTS"/spire-server.port)"       \
         "$_template"                                                         \
         "$_j2"                                                               \
      > "$_manifest"

  $DRY_RUN kubectl "$KSA_MODE"                                                \
  --context "$KSA_CONTEXT"                                                    \
  -f "$_spire_bundle"

  if is_create_mode; then
    # shellcheck disable=SC2086
    $DRY_RUN helm upgrade --install spire-agent spire/spire                   \
    --version "$SPIRE_SERVER_VER"                                             \
    --kube-context="$KSA_CONTEXT"                                             \
    --namespace "$SPIRE_NAMESPACE"                                            \
    --values "$_manifest"                                                     \
    --wait

    $DRY_RUN kubectl wait                                                     \
    --namespace "$SPIRE_NAMESPACE"                                            \
    --for=condition=Ready pods --all
  else
    $DRY_RUN helm uninstall spire-agent                                       \
    --kube-context="$KSA_CONTEXT"                                             \
    --namespace "$SPIRE_NAMESPACE"
  fi

  cp "$_cid_template"                                                         \
     "$_cid_manifest"

  $DRY_RUN kubectl "$KSA_MODE"                                                \
  --context "$KSA_CONTEXT"                                                    \
  -f "$MANIFESTS"/spire.cluster-id."$KSA_CLUSTER".yaml
}

function exec_exchange_bundles {
  local _cmd; _cmd=$(mktemp)
  local _remote_trust_bundle

    cat <<EOF >> "$_cmd"
_remote_trust_bundle=\$(kubectl exec spire-server-0                            \
--namespace "\$SPIRE_NAMESPACE"                                                \
--context "\$KSA_REMOTE_CONTEXT"                                               \
-- spire-server bundle show -format spiffe)

kubectl exec spire-server-0                                                    \
--namespace "\$SPIRE_NAMESPACE"                                                \
--context "\$KSA_CONTEXT"                                                      \
-- spire-server bundle set                                                     \
   -format spiffe                                                              \
   -id "spiffe://\${REMOTE_TRUST_DOMAIN}"                                      \
<<< "\$_remote_trust_bundle"
EOF

  _f_debug "$_cmd"
}
