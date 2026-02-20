#!/usr/bin/env bash
###############################################################################
# execs.sh
#
# like installs.sh, but every function takes care of its own destructor if
# GSI_MODE is set to "delete"
###############################################################################
function exec_tls_cert_secret {
  local _cluster _namespace _secret_name _context

  while getopts "c:n:s:x:" opt; do
    # shellcheck disable=SC2220
    case $opt in
      c)
        _cluster=$OPTARG ;;
      n)
        _namespace=$OPTARG ;;
      s)
        _secret_name=$OPTARG ;;
      x)
        _context=$OPTARG ;;
    esac
  done

  [[ -z $_context ]] && _context="$_cluster"

  if is_create_mode; then
    $DRY_RUN kubectl "$GSI_MODE" secret tls "$_secret_name"                   \
    --context "$GSI_CONTEXT"                                                  \
    --namespace "$_namespace"                                                 \
    --cert="${CERTS}"/"${_cluster}"/ca-cert.pem                               \
    --key="${CERTS}"/"${_cluster}"/ca-key.pem
  else
    $DRY_RUN kubectl "$GSI_MODE" secret "$_secret_name"                       \
    --context "$GSI_CONTEXT"                                                  \
    --namespace "$_namespace"
  fi
}

function exec_issuer_ingress_gateways {
  create_issuer -m "$INGRESS_GATEWAY_NAME"                                    \
                -n "$INGRESS_NAMESPACE"                                       \
                -s "$CERT_MANAGER_INGRESS_SECRET"                             \
                -c "US"                                                       \
                -l "Sunnyvale"                                                \
                -o "DVE"                                                      \
                -p "CA"                                                       \
                -u "Development"      
}

function exec_issuer_istio_ingress_gateway {
  create_issuer -m "$GSI_APP_SERVICE_NAME"                                    \
                -n "$GSI_APP_SERVICE_NAMESPACE"                               \
                -s "$GSI_APP_GATEWAY_SECRET"                                  \
                -c "US"                                                       \
                -l "Sunnyvale"                                                \
                -o "Solo IO"                                                  \
                -p "CA"                                                       \
                -u "Customer Success"
}

# END
