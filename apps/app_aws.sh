#!/usr/bin/env bash

function app_init_aws {
  if $AWS_ENABLED; then
    if $AWS_PCA_ENABLED; then
      exec_initialize_root_pca
    fi

    if $AWS_COGNITO_ENABLED; then
      exec_cognito_route_option
    fi
  fi
}

function app_init_acmpca {
  create_aws_intermediate_pca Istio
  create_aws_pca_issuer_role Istio
  exec_aws_pca_serviceaccount
  exec_aws_pca_privateca_issuer
  create_aws_pca_issuer -c istio -n istio-system -a "$SUBORDINATE_CAARN"
  ### create_aws_pca_cluster_issuer -c istio -n default -a "$ROOT_CAARN" # -a "$SUBORDINATE_CAARN"
  exec_istio_awspca_secrets
}

function exec_initialize_root_pca {
  local _cmd; _cmd=$(mktemp)
  local _ca_manifest="$MANIFESTS"/aws.pca_ca_config_root_ca.json
  local _ca_template="$TEMPLATES"/aws/pca_ca_config_root_ca.json
  local _ca_arn="$MANIFESTS/root-ca.arn"
  local _ca_csr="$MANIFESTS/root-ca.csr"
  local _ca_pem="$MANIFESTS/root-ca.pem"

  ROOT_CERT_VALIDITY_IN_DAYS=3650

  if [[ $DRY_RUN == echo ]]; then
    echo "ROOT_CERT_VALIDITY_IN_DAYS=$ROOT_CERT_VALIDITY_IN_DAYS"
  fi
  
  cp "$_ca_template"                                                          \
     "$_ca_manifest"

  ROOT_CAARN=$(aws acm-pca list-certificate-authorities                       \
  --profile aws                                                               \
  --region us-west-2                                                         |\
  jq -r '.CertificateAuthorities[]     |
         select (.Type =="ROOT")       |
         select(.Status == "ACTIVE")   |
         select(.CertificateAuthorityConfiguration.Subject.OrganizationalUnit == "Customer Success") | 
         .Arn')
  if [[ -n $ROOT_CAARN ]]; then
    echo -n "$ROOT_CAARN" > "$_ca_arn"
    echo '# '"ROOT_CAARN=$ROOT_CAARN"
  fi

  if is_create_mode && [[ -z $ROOT_CAARN ]]; then
    # https://docs.aws.amazon.com/cli/latest/reference/acm-pca/create-certificate-authority.html
    # shellcheck disable=SC2129
    cat <<EOF >> "$_cmd"

echo '# Create root private certificate authority (CA)'
ROOT_CAARN=\$(aws acm-pca create-certificate-authority                        \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-configuration file://"$_ca_manifest" \\
--certificate-authority-type "ROOT"                                          \\
--idempotency-token 01234567                                                 \\
--output json                                                                \\
--tags Key=Name,Value=RootCA                                                |\\
jq -r '.CertificateAuthorityArn')
echo '# Sleep for 15 seconds while CA creation completes'
sleep 15
echo '# '"ROOT_CAARN=\$ROOT_CAARN"
echo -n \$ROOT_CAARN > "$_ca_arn"
EOF

    # https://docs.aws.amazon.com/cli/latest/reference/acm-pca/get-certificate-authority-csr.html
    cat <<EOF >> "$_cmd"

echo '# Download Root CA CSR from AWS'
aws acm-pca get-certificate-authority-csr                                    \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$ROOT_CAARN"                                    \\
--output text > "$_ca_csr"
EOF

    # https://docs.aws.amazon.com/cli/latest/reference/acm-pca/issue-certificate.html
    cat <<EOF >> "$_cmd"

echo '# Issue Root Certificate. Valid for \$ROOT_CERT_VALIDITY_IN_DAYS days'
ROOT_CERTARN=\$(aws acm-pca issue-certificate                                 \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$ROOT_CAARN"                                    \\
--csr fileb://"$_ca_csr"                             \\
--signing-algorithm "SHA256WITHRSA"                                          \\
--template-arn arn:aws:acm-pca:::template/RootCACertificate/V1               \\
--validity "Value=\$ROOT_CERT_VALIDITY_IN_DAYS,Type=DAYS"                     \\
--idempotency-token 1234567                                                  \\
--output json                                                               |\\
jq -r '.CertificateArn')
echo '#'"Sleep for 15 seconds while cert issuance completes"
sleep 15
echo '# '"ROOT_CERTARN=\$ROOT_CERTARN"
EOF

    # https://docs.aws.amazon.com/cli/latest/reference/acm-pca/get-certificate.html
    cat <<EOF >> "$_cmd"

echo '# Retrieve root certificate from private CA and save locally'
aws acm-pca get-certificate                                                  \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$ROOT_CAARN"                                    \\
--certificate-arn "\$ROOT_CERTARN"                                            \\
--output text > "$_ca_pem"
EOF

    # https://docs.aws.amazon.com/cli/latest/reference/acm-pca/import-certificate-authority-certificate.html
    cat <<EOF >> "$_cmd"

echo '# Import the signed Private CA certificate for the CA specified by the ARN into ACM PCA'
aws acm-pca import-certificate-authority-certificate                         \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$ROOT_CAARN"                                    \\
--certificate fileb://"$_ca_pem"
EOF
####  else
####    cat <<EOF >> "$_cmd"
####aws acm-pca update-certificate-authority                                     \\
####--profile "\$AWS_PROFILE"                                                     \\
####--region "\$AWS_REGION"                                                       \\
####--certificate-authority-arn "$(cat "$_ca_arn")"                               \\
####--status DISABLED
####
####aws acm-pca delete-certificate-authority                                     \\
####--profile "\$AWS_PROFILE"                                                     \\
####--region "\$AWS_REGION"                                                       \\
####--certificate-authority-arn "$(cat "$_ca_arn")"
####EOF
  fi

  _f_debug "$_cmd"
}

###
# INTERMEDIATE CA and CERT (aka subordinate ca and cert)
###
function create_aws_intermediate_pca {
  local _cmd; _cmd=$(mktemp)

  local _component=$1
  local _ca_manifest="$MANIFESTS"/aws.pca_ca_config_intermediate_ca."${_component}".json
  local _ca_template="$TEMPLATES"/aws/pca_ca_config_intermediate_ca.json.j2
  local _ca_arn="$MANIFESTS/intermediate_ca.${_component}.arn"
  local _ca_csr="$MANIFESTS/intermediate_ca.${_component}.csr"
  local _ca_pem="$MANIFESTS/intermediate-cert.${_component}.pem"
  local _cert_chain_pem="$MANIFESTS/intermediate-cert-chain.${_component}.pem"
  SUBORDINATE_CERT_VALIDITY_IN_DAYS=1825

  if [[ $DRY_RUN == echo ]]; then
    echo SUBORDINATE_CERT_VALIDITY_IN_DAYS=$SUBORDINATE_CERT_VALIDITY_IN_DAYS
  fi

  jinja2 -D component="$_component"                                           \
         "$_ca_template"                                                      \
  > "$_ca_manifest"

  SUBORDINATE_CAARN=$(aws acm-pca list-certificate-authorities                \
  --profile aws                                                               \
  --region us-west-2                                                         |\
  jq -r '.CertificateAuthorities[]            |
         select (.Type =="SUBORDINATE")       |
         select(.Status == "ACTIVE")          |
         select(.CertificateAuthorityConfiguration.Subject.OrganizationalUnit == "Customer Success") | 
         .Arn')
  if [[ -n $SUBORDINATE_CAARN ]]; then
    echo -n "$SUBORDINATE_CAARN" > "$_ca_arn"
    echo '# '"SUBORDINATE_CAARN=$SUBORDINATE_CAARN"
  fi

  if is_create_mode && [[ -z $SUBORDINATE_CAARN ]]; then
    # https://docs.aws.amazon.com/cli/latest/reference/acm-pca/create-certificate-authority.html
    # shellcheck disable=SC2129
    cat <<EOF >> "$_cmd"

echo '# '"Create Intermediate private certificate authority (CA) for $_component"
SUBORDINATE_CAARN=\$(                                                        \\
aws acm-pca create-certificate-authority                                     \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-configuration file://"$_ca_manifest" \\
--tags Key=Name,Value="SubordinateCA-${_component}"                          \\
--certificate-authority-type "SUBORDINATE"                                   \\
--idempotency-token 01234567                                                |\\
jq -r '.CertificateAuthorityArn')
echo '# Sleep for 15 seconds while Intermediate CA creation completes'
sleep 15
echo '# '"SUBORDINATE_CAARN=\$SUBORDINATE_CAARN"
echo -n \$SUBORDINATE_CAARN > "$_ca_arn"
EOF

    # https://docs.aws.amazon.com/cli/latest/reference/acm-pca/get-certificate-authority-csr.html
    cat <<EOF >> "$_cmd"

echo '# Download Intermediate CA CSR from AWS'
aws acm-pca get-certificate-authority-csr                                    \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$SUBORDINATE_CAARN"                             \\
--output text > "$_ca_csr"
EOF

    cat <<EOF >> "$_cmd"

echo '# '"Issue Intermediate Certificate for $_component. Valid for \$SUBORDINATE_CERT_VALIDITY_IN_DAYS days"
SUBORDINATE_CERTARN=\$(                                                       \\
aws acm-pca issue-certificate                                                \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$ROOT_CAARN"                                    \\
--csr fileb://"$_ca_csr"                                                     \\
--signing-algorithm "SHA256WITHRSA"                                          \\
--template-arn arn:aws:acm-pca:::template/SubordinateCACertificate_PathLen1/V1 \\
--validity "Value=\$SUBORDINATE_CERT_VALIDITY_IN_DAYS,Type=DAYS"              \\
--idempotency-token 1234567                                                  \\
--output json                                                               |\\
jq -r '.CertificateArn')
echo '# Sleep for 15 seconds while cert issuance completes'
sleep 15
echo '# '"SUBORDINATE_CERTARN=\$SUBORDINATE_CERTARN"
EOF

    cat <<EOF >> "$_cmd"

'# Retrieve Intermediate certificate from private CA and save locally'
aws acm-pca get-certificate                                                  \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$ROOT_CAARN"                                    \\
--certificate-arn "\$SUBORDINATE_CERTARN"                                     \\
--output json                                                               |\\
jq -r '.Certificate' > "$_ca_pem"
EOF

    cat <<EOF >> "$_cmd"
echo '#'"Retrieve Intermediate certificate chain from private CA and save locally"
aws acm-pca get-certificate                                                  \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$ROOT_CAARN"                                    \\
--certificate-arn "\$SUBORDINATE_CERTARN"                                     \\
--output json                                                               |\\
jq -r '.CertificateChain' > "$_cert_chain_pem"
EOF

    cat <<EOF >> "$_cmd"
echo '#'"Import the certificate into ACM PCA"
aws acm-pca import-certificate-authority-certificate                         \\
--profile "\$AWS_PROFILE"                                                     \\
--region "\$AWS_REGION"                                                       \\
--certificate-authority-arn "\$SUBORDINATE_CAARN"                             \\
--certificate fileb://"$_ca_pem"                                             \\
--certificate-chain fileb://"$_cert_chain_pem"
EOF
####  else
####    cat <<EOF >> "$_cmd"
####aws acm-pca update-certificate-authority                                     \\
####--profile "\$AWS_PROFILE"                                                     \\
####--region "\$AWS_REGION"                                                       \\
####--certificate-authority-arn "$(cat "$_ca_arn")"                               \\
####--status DISABLED
####
####aws acm-pca delete-certificate-authority                                     \\
####--profile "\$AWS_PROFILE"                                                     \\
####--region "\$AWS_REGION"                                                       \\
####--certificate-authority-arn "$(cat "$_ca_arn")"
####EOF
  fi

  _f_debug "$_cmd"
}

function create_aws_pca_issuer_role {
  local _cmd; _cmd=$(mktemp)
  local _component=$1
  local _policy_manifest="$MANIFESTS/aws.AWSPCAIssuerPolicy.${_component}.${KSA_CLUSTER}.json"
  local _policy_template="$TEMPLATES"/aws/AWSPCAIssuerPolicy.json.j2
  local _assume_manifest="$MANIFESTS/aws.AWSPCAAssumeRole.${_component}.${KSA_CLUSTER}.json"
  local _assume_template="$TEMPLATES"/aws/AWSPCAAssumeRole.json.j2
  local _policy_arn="$MANIFESTS/AWSPCAIssuerPolicy.${_component}.${KSA_CLUSTER}.arn"
  local _assume_arn="$MANIFESTS/AWSPCAAssumeRole.${_component}.${KSA_CLUSTER}.arn"

  local _partition _account_id _oidc_issuer

  _partition=$(aws --profile aws --region us-west-2 sts get-caller-identity |jq -r '.Arn'|awk -F: '{print $2}')
  _account_id=$(aws --profile aws --region us-west-2 sts get-caller-identity |jq -r '.Account')
  _oidc_issuer=$(aws eks describe-cluster                                     \
  --profile "$AWS_PROFILE"                                                    \
  --region "$AWS_REGION"                                                      \
  --name "$KSA_CLUSTER"                                                       |
  jq -r '.cluster.identity.oidc.issuer'                                       |
  sed -e 's;https://\(.*\);\1;')

  jinja2 -D ca_root_arn="$ROOT_CAARN"                                         \
         -D ca_sub_arn="$SUBORDINATE_CAARN"                                   \
         "$_policy_template"                                                  \
  > "$_policy_manifest"

  jinja2 -D partition="$_partition"                                           \
         -D account_id="$_account_id"                                         \
         -D oidc_issuer="$_oidc_issuer"                                       \
         "$_assume_template"                                                  \
  > "$_assume_manifest"

  if is_create_mode; then
    # shellcheck disable=SC2129
    cat <<EOF >> "$_cmd"

# Create AWS Role and service account w/o eksctl
AWS_PCA_POLICY_ARN=\$(aws iam create-policy                                   \\
  --profile "\$AWS_PROFILE"                                                   \\
  --region "\$AWS_REGION"                                                     \\
  --policy-name AWSPCAIssuerPolicy-"$_component-$KSA_CLUSTER-$UTAG"          \\
  --policy-document file://"$_policy_manifest"                               \\
  --output json                                                             |\\
  jq -r '.Policy.Arn')
echo '# '"AWS_PCA_POLICY_ARN=\$AWS_PCA_POLICY_ARN"
echo -n \$AWS_PCA_POLICY_ARN > "$_policy_arn"

AWS_PCA_ROLE_ARN=\$(aws iam create-role                                       \\
  --profile "\$AWS_PROFILE"                                                   \\
  --region "\$AWS_REGION"                                                     \\
  --role-name "$KSA_CLUSTER"-pca-issuer                                      \\
  --assume-role-policy-document file://"$_assume_manifest"                   \\
  --output json                                                             |\\
  jq -r '.Role.Arn')
echo '# '"AWS_PCA_ROLE_ARN=\$AWS_PCA_ROLE_ARN"
echo -n \$AWS_PCA_ROLE_ARN > "$_assume_arn"

aws iam attach-role-policy                                                   \\
  --profile "\$AWS_PROFILE"                                                   \\
  --region "\$AWS_REGION"                                                     \\
  --policy-arn "\$AWS_PCA_POLICY_ARN"                                         \\
  --role-name "$KSA_CLUSTER"-pca-issuer
EOF
  else
    cat <<EOF >> "$_cmd"
aws iam detach-role-policy                                                   \\
  --profile "\$AWS_PROFILE"                                                   \\
  --region "\$AWS_REGION"                                                     \\
  --policy-arn "\$AWS_PCA_POLICY_ARN"                                         \\
  --role-name "$KSA_CLUSTER"-pca-issuer

aws iam delete-role                                                          \\
  --profile "\$AWS_PROFILE"                                                   \\
  --region "\$AWS_REGION"                                                     \\
  --role-name "$KSA_CLUSTER"-pca-issuer

aws iam delete-policy                                                        \\
  --profile "\$AWS_PROFILE"                                                   \\
  --region "\$AWS_REGION"                                                     \\
  --policy-arn "$(cat "$_policy_arn")"
EOF
    
  fi
  _f_debug "$_cmd"
}

function exec_aws_pca_serviceaccount {
    $DRY_RUN kubectl "$KSA_MODE" serviceaccount aws-pca-issuer                \
    --context "$KSA_CONTEXT"                                                  \
    --namespace "$CERT_MANAGER_NAMESPACE"

    $DRY_RUN kubectl annotate serviceaccount aws-pca-issuer                   \
    "eks.amazonaws.com/role-arn=${AWS_PCA_ROLE_ARN}"                          \
    --context "$KSA_CONTEXT"                                                  \
    --namespace "$CERT_MANAGER_NAMESPACE"
}

function exec_aws_pca_privateca_issuer {
  if is_create_mode; then
    $DRY_RUN helm upgrade --install aws-pca-issuer awspca/aws-privateca-issuer \
    --version "$AWSPCA_ISSUER_VER"                                            \
    --kube-context="$KSA_CONTEXT"                                             \
    --namespace "$CERT_MANAGER_NAMESPACE"                                     \
    --set serviceAccount.create=false                                         \
    --set serviceAccount.name="aws-pca-issuer"                                \
    --set image.tag="$AWSPCA_ISSUER_VER"                                      \
    --set podLabels.app=aws-pca-issuer                                        \
    --wait
  else
    $DRY_RUN helm uninstall aws-pca-issuer                                    \
    --kube-context="$KSA_CONTEXT"                                             \
    --namespace "$CERT_MANAGER_NAMESPACE"
  fi

  if is_create_mode; then
    $DRY_RUN sleep 1
    $DRY_RUN kubectl wait                                                     \
    --context "$KSA_CONTEXT"                                                  \
    --namespace "$CERT_MANAGER_NAMESPACE"                                     \
    --for=condition=Ready pods -l app=aws-pca-issuer
  fi
}

function create_aws_pca_issuer {
  local _component _namespace _ca_arn

  while getopts "a:c:n:" opt; do
    # shellcheck disable=SC2220
    case $opt in
      a)
        _ca_arn=$OPTARG ;;
      c)
        _component=$OPTARG ;;
      n)
        _namespace=$OPTARG ;;
    esac
  done
  local _manifest="$MANIFESTS"/aws.awspca_issuer."$_component"."$_namespace"."$KSA_CLUSTER".yaml
  local _template="$TEMPLATES"/aws/awspca_issuer.manifest.yaml.j2
  export AWSPCA_ISSUER="aws-pca-issuer-${_component}"
  export AWSPCA_ISSUER_KIND="AWSPCAIssuer"

  jinja2 -D name="$AWSPCA_ISSUER"                                              \
         -D namespace="$_namespace"                                            \
         -D ca_arn="$_ca_arn"                                                  \
         -D ca_region="us-west-2"                                              \
         "$_template"                                                          \
  > "$_manifest"

  $DRY_RUN kubectl "$KSA_MODE"                                                 \
  --context "$KSA_CONTEXT"                                                     \
  -f "$_manifest"
}

function create_aws_pca_cluster_issuer {
  local _component _namespace _ca_arn

  while getopts "a:c:n:" opt; do
    # shellcheck disable=SC2220
    case $opt in
      a)
        _ca_arn=$OPTARG ;;
      c)
        _component=$OPTARG ;;
      n)
        _namespace=$OPTARG ;;
    esac
  done

  local _manifest="$MANIFESTS"/aws.awspca_cluster_issuer."$_component"."$_namespace"."$KSA_CLUSTER".yaml
  local _template="$TEMPLATES"/aws/awspca_cluster_issuer.manifest.yaml.j2
  export AWSPCA_ISSUER="aws-pca-cluster-issuer-${_component}"
  export AWSPCA_ISSUER_KIND="AWSPCAClusterIssuer"

  jinja2 -D name="$AWSPCA_ISSUER"                                             \
         -D namespace="$_namespace"                                           \
         -D ca_arn="$_ca_arn"                                                 \
         -D ca_region="us-west-2"                                             \
         "$_template"                                                          \
  > "$_manifest"

  $DRY_RUN kubectl "$KSA_MODE"                                                \
  --context "$KSA_CONTEXT"                                                    \
  -f "$_manifest"
}
# END

function exec_cognito_route_option {
  local _manifest="$MANIFESTS"/aws.route_option.cognitio."$KSA_CLUSTER".yaml
  local _template="$TEMPLATES"/aws/route_options.cognito.manifest.yaml.j2

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
}
