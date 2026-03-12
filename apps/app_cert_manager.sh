#!/usr/bin/env bash
function app_init_cert_manager {
  if $CERT_MANAGER_ENABLED; then
    echo '# '"$0"
    $ITER_MC exec_cert_manager
  fi
}

function exec_cert_manager_secrets {
  if is_create_mode; then
    $DRY_RUN kubectl create secret generic "$CERT_MANAGER_INGRESS_SECRET"      \
    --context "$KSA_CONTEXT"                                                   \
    --namespace "$CERT_MANAGER_NAMESPACE"                                      \
    --from-file=tls.crt="$CERT_MANAGER_CERTS"/root-cert.pem                    \
    --from-file=tls.key="$CERT_MANAGER_CERTS"/root-key.pem
  else
    $DRY_RUN kubectl "$KSA_MODE" secret "$CERT_MANAGER_SECRET"                 \
    --context "$KSA_CONTEXT"                                                   \
    --namespace "$CERT_MANAGER_NAMESPACE"
  fi
}

function exec_cert_manager {
  local _manifest="$MANIFESTS/helm.cert-manager.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/cert-manager/helm.values.yaml.j2

  _make_manifest "$_template" > "$_manifest"

  if is_create_mode; then

    $DRY_RUN helm upgrade --install cert-manager "$CERT_MANAGER_HELM_REPO"     \
    --version "$CERT_MANAGER_VER"                                              \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$CERT_MANAGER_NAMESPACE"                                      \
    --create-namespace                                                         \
    --values "$_manifest"                                                      \
    --wait
  else 
    $DRY_RUN helm uninstall cert-manager                                       \
    --kube-context="$KSA_CONTEXT"                                             \
    --namespace "$CERT_MANAGER_NAMESPACE"
  fi

  if is_create_mode; then
    $DRY_RUN kubectl wait                                                     \
    --context="$KSA_CONTEXT"                                                  \
    --namespace "$CERT_MANAGER_NAMESPACE"                                     \
    --for=condition=Ready pods --all
  fi
}

function exec_cert_manager_ingress_issuer {

  local _manifest="$MANIFESTS/cert-manager.issuer.ingress.manifest${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/cert-manager/issuer.ingress.manifest.yaml.j2

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
}

function exec_cert_manager_ingress_certificate {

  local _manifest="$MANIFESTS/cert-manager.certificate.ingress.manifest${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/cert-manager/certificate.ingress.manifest.yaml.j2

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
}

function exec_cert_manager_cluster_issuer {
  local _manifest="$MANIFESTS/cert-manager.cluster_issuer.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/cert-manager/cluster_issuer.manifest.yaml.j2

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
}

function create_cert_manager_issuer {
    local _name _namespace _org _secret_name _country _locale _state _ou

    while getopts "c:l:m:n:o:p:s:u:" opt; do
    # shellcheck disable=SC2220
    case $opt in
      c)
        _country=$OPTARG ;;
      l)
        _locale=$OPTARG ;;
      m)
        _name=$OPTARG ;;
      n)
        _namespace=$OPTARG ;;
      o)
        _org=$OPTARG ;;
      p)
        _state=$OPTARG ;;
      s)
        _secret_name=$OPTARG ;;
      u)
        _ou=$OPTARG ;;
    esac
  done

  local _manifest="$MANIFESTS/cert-manager/issuer.${_name}.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/cert-manager/issuer.manifest.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  jinja2                                                                      \
         -D serial_no="$(date +%Y%m%d)"                                       \
         "$_template"                                                         \
         "$_j2"                                                               \
  > "$_manifest"

  jinja2 -D name="$_name"                                                     \
         -D namespace="$_namespace"                                           \
         -D org="$_org"                                                       \
         -D ou="$_ou"                                                         \
         -D country="$_country"                                               \
         -D state="$_state"                                                   \
         -D locale="$_locale"                                                 \
         -D secret_name="$_secret_name"                                       \
         "$_template"                                                         \
    > "$_manifest"

  $DRY_RUN kubectl "$KSA_MODE"                                                \
  --context "$KSA_CONTEXT"                                                    \
  -f "$_manifest" 
}
