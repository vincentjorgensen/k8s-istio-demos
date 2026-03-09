#!/usr/bin/env bash
function app_init_istio {
  if $ISTIO_ENABLED; then
    echo '# '"$0"
    if $AWS_PCA_ENABLED && $CERT_MANAGER_ENABLED; then
      $ITER_MC app_init_acmpca
    else
      if ! $SPIRE_ENABLED; then
        $ITER_MC exec_istio_secrets
      fi
      $ITER_MC exec_istio
      $ITER_MC exec_telemetry_defaults
    fi
  fi
}

function exec_istio_secrets {
  if is_create_mode; then
    $DRY_RUN kubectl create secret generic "$ISTIO_SECRET"                     \
    --context "$GSI_CONTEXT"                                                   \
    --namespace "$ISTIO_NAMESPACE"                                             \
    --from-file="$CERTS"/"$GSI_CLUSTER"/ca-cert.pem                            \
    --from-file="$CERTS"/"$GSI_CLUSTER"/ca-key.pem                             \
    --from-file="$CERTS"/"$GSI_CLUSTER"/root-cert.pem                          \
    --from-file="$CERTS"/"$GSI_CLUSTER"/cert-chain.pem
  else
    $DRY_RUN kubectl "$GSI_MODE" secret cacerts                                \
    --context "$GSI_CONTEXT"                                                   \
    --namespace "$ISTIO_NAMESPACE"
  fi
}

function exec_istio_awspca_secrets {
  local _manifest="$MANIFESTS"/certificate.cert-manager."$GSI_CLUSTER".yaml
  local _template="$TEMPLATES"/certificate.cert-manager.manifest.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$GSI_CLUSTER".yaml

  jinja2 -D awspca_component="istio"                                          \
         -D awspca_issuer="$AWSPCA_ISSUER"                                    \
         -D awspca_issuer_kind="$AWSPCA_ISSUER_KIND"                          \
         -D trust_domain="$TRUST_DOMAIN"                                      \
         "$_template"                                                         \
         "$_j2"                                                               \
  > "$_manifest"

  $DRY_RUN kubectl "$GSI_MODE"                                                \
  --context "$GSI_CONTEXT"                                                    \
  -f "$_manifest"
}

function exec_istio_base {
  local _cluster=$GSI_CLUSTER
  local _context=$GSI_CONTEXT

  while getopts "c:x:" opt; do
    # shellcheck disable=SC2220
    case $opt in
      c)
        _cluster=$OPTARG ;;
      x)
        _context=$OPTARG ;;
    esac
  done

  local _manifest="$MANIFESTS/helm.istio-base.${_cluster}.yaml"
  local _template="$TEMPLATES"/istio/helm.istio-base.yaml.j2

  if is_create_mode; then
    _make_manifest "$_template" > "$_manifest"

    # shellcheck disable=SC2086
    $DRY_RUN helm upgrade --install istio-base "$HELM_REPO"/base              \
    --version "${ISTIO_VER}${ISTIO_FLAVOR}"                                   \
    --kube-context="$_context"                                                \
    --namespace "$ISTIO_NAMESPACE"                                     \
    --create-namespace                                                        \
    --values "$_manifest"                                                     \
    --wait
  else
    $DRY_RUN helm uninstall istio-base                                        \
    --kube-context="$_context"                                                \
    --namespace "$ISTIO_NAMESPACE"
  fi
}

function exec_istio_istiod {
  local _manifest="$MANIFESTS/helm.istiod.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/istio/helm.istiod.yaml.j2

  if is_create_mode; then
    _make_manifest "$_template" > "$_manifest"

    $DRY_RUN helm upgrade --install istiod "$HELM_REPO"/istiod                \
    --version "${ISTIO_VER}${ISTIO_FLAVOR}"                                   \
    --kube-context="$GSI_CONTEXT"                                             \
    --namespace "$ISTIO_NAMESPACE"                                     \
    --values "$_manifest"                                                     \
    --wait
  else
    $DRY_RUN helm uninstall istiod                                            \
    --kube-context="$GSI_CONTEXT"                                             \
    --namespace "$ISTIO_NAMESPACE"
  fi
}

function exec_istio_cni {
  local _manifest="$MANIFESTS/helm.istio-cni.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/istio/helm.istio-cni.yaml.j2

  if is_create_mode; then
    _make_manifest "$_template" > "$_manifest"

    $DRY_RUN helm upgrade --install istio-cni "$HELM_REPO"/cni                \
    --version "${ISTIO_VER}${ISTIO_FLAVOR}"                                   \
    --kube-context="$GSI_CONTEXT"                                             \
    --namespace "$ISTIO_NAMESPACE"                                     \
    --values "$_manifest"                                                     \
    --wait
  else
    $DRY_RUN helm uninstall istio-cni                                         \
    --kube-context="$GSI_CONTEXT"                                             \
    --namespace "$ISTIO_NAMESPACE"
  fi
}

function exec_istio_ztunnel {
  local _manifest="$MANIFESTS/helm.ztunnel.${GSI_CLUSTER}.yaml"
  local _template="$TEMPLATES"/istio/helm.ztunnel.yaml.j2

  if is_create_mode; then
    _make_manifest "$_template" > "$_manifest"

    $DRY_RUN helm upgrade --install ztunnel "$HELM_REPO"/ztunnel               \
    --version "${ISTIO_VER}${ISTIO_FLAVOR}"                                    \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$ISTIO_NAMESPACE"                                             \
    --values "$_manifest"                                                      \
    --wait
  else
    $DRY_RUN helm uninstall ztunnel                                            \
    --kube-context="$GSI_CONTEXT"                                              \
    --namespace "$ISTIO_NAMESPACE"
  fi
}

function exec_telemetry_defaults {
  local _manifest="$MANIFESTS"/telemetry.istio-system."$GSI_CLUSTER".yaml
  local _template="$TEMPLATES"/istio/telemetry.istio-system.manifest.yaml

  cp "$_template"                                                              \
     "$_manifest"

  _apply_manifest "$_manifest"
}

function exec_istio {
  local _k_label="=$GSI_NETWORK"

  if ! is_create_mode; then
    _k_label="-"
  fi

  if $MULTICLUSTER_ENABLED; then
    _label_namespace "$ISTIO_NAMESPACE" "topology.istio.io/network" "$GSI_NETWORK"
  fi

  exec_istio_base
  exec_istio_istiod
  "$AMBIENT_ENABLED" || $INTEROP_ENABLED && exec_istio_cni
  "$AMBIENT_ENABLED" || $INTEROP_ENABLED && exec_istio_ztunnel

  if is_create_mode; then
    $DRY_RUN kubectl wait                                                      \
    --context "$GSI_CONTEXT"                                                   \
    --namespace "$ISTIO_NAMESPACE"                                             \
    --for=condition=Ready pods --all
  fi
}

function exec_peer_authentication {
  local _manifest="$MANIFESTS"/istio.peer_authentication."$GSI_CLUSTER".yaml
  local _template="$TEMPLATES"/istio/peer_authentication.manifest.yaml.j2

  if [[ $ISTIO_PEER_AUTH_MODE == STRICT ]]; then
    _label_namespace "$ISTIO_NAMESPACE" "topology.istio.io/network" "$GSI_NETWORK"
  fi

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
}
