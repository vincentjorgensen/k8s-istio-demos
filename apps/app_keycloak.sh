#!/usr/bin/env bash
function app_init_keycloak {
  if $KEYCLOAK_ENABLED; then
    echo '# '"$0"
    exec_keycloak
    exec_initialize_keycloak
  fi
}
function exec_keycloak {
  local _manifest="$MANIFESTS/keycloak.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/keycloak.manifest.yaml.j2

  _make_manifest "$_template" > "$_manifest"
  _apply_manifest "$_manifest"
  _wait_for_pods "$KSA_CONTEXT" "$KEYCLOAK_NAMESPACE" keycloak
}

function set_keycloak_token_client_and_secret {
  KEYCLOAK_TOKEN=$(curl -d "client_id=admin-cli" -d "username=admin"          \
                        -d "password=admin" -d "grant_type=password"          \
                  "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" |
                   jq -r .access_token)

  #shellcheck disable=SC2046
  read -r client token <<<$(curl -H "Authorization: Bearer $KEYCLOAK_TOKEN"   \
                            -X POST -H "Content-Type: application/json"       \
                            -d '{"expiration": 0, "count": 1}'                \
                   "$KEYCLOAK_URL/admin/realms/master/clients-initial-access" |
                   jq -r '[.id, .token] | @tsv')
  KEYCLOAK_CLIENT="$client"

  #shellcheck disable=SC2046
  read -r id secret <<<$(curl -k -X POST                                      \
                              -d "{ \"clientId\": \"${KEYCLOAK_CLIENT}\" }"   \
                              -H "Content-Type:application/json"              \
                              -H "Authorization: bearer ${token}"             \
                  "$KEYCLOAK_URL/realms/master/clients-registrations/default" |
                  jq -r '[.id, .secret] | @tsv')
  KEYCLOAK_SECRET="$secret"
  KEYCLOAK_ID="$id"
  echo '#' KEYCLOAK_TOKEN="$KEYCLOAK_TOKEN"
  echo '#' KEYCLOAK_CLIENT="$KEYCLOAK_CLIENT"
  echo '#' KEYCLOAK_SECRET="$KEYCLOAK_SECRET"
  echo '#' KEYCLOAK_ID="$KEYCLOAK_ID"
}

function exec_initialize_keycloak {
  KEYCLOAK_ENDPOINT=$(kubectl get service keycloak                            \
    --context "$KSA_CONTEXT"                                                  \
    --namespace "$KEYCLOAK_NAMESPACE"                                         \
    -o=jsonpath="{.status.loadBalancer.ingress[0]['hostname','ip']}"):8080
###  KEYCLOAK_HOST=$(echo "${KEYCLOAK_ENDPOINT}" | cut -d: -f1)
###  KEYCLOAK_PORT=$(echo "${KEYCLOAK_ENDPOINT}" | cut -d: -f2)
  KEYCLOAK_URL=http://"${KEYCLOAK_ENDPOINT}"

  set_keycloak_token_client_and_secret # sets KEYCLOAK_TOKEN, KEYCLOAK_CLIENT, KEYCLOAK_SECRET, KEYCLOAK_ID

  # Add allowed redirect URIs
  curl -k -H "Authorization: Bearer $KEYCLOAK_TOKEN" -X PUT                   \
       -H "Content-Type: application/json"                                    \
       -d '{"serviceAccountsEnabled": true, "directAccessGrantsEnabled": true, "authorizationServicesEnabled": true, "redirectUris": ["*"]}' \
       "$KEYCLOAK_URL/admin/realms/master/clients/$KEYCLOAK_ID"

  # Add the group attribute in the JWT token returned by Keycloak
  curl -H "Authorization: Bearer $KEYCLOAK_TOKEN" -X POST                     \
       -H "Content-Type: application/json"                                    \
       -d '{"name": "group", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-attribute-mapper", "config": {"claim.name": "group", "jsonType.label": "String", "user.attribute": "group", "id.token.claim": "true", "access.token.claim": "true"}}' \
       "$KEYCLOAK_URL/admin/realms/master/clients/$KEYCLOAK_ID/protocol-mappers/models"

  # Create first user
  curl -H "Authorization: Bearer $KEYCLOAK_TOKEN" -X POST                     \
       -H "Content-Type: application/json"                                    \
       -d '{"username": "user1", "email": "user1@example.com", "firstName": "Alice", "lastName": "Doe", "enabled": true, "attributes": {"group": "users"}, "credentials": [{"type": "password", "value": "password", "temporary": false}]}' \
       "$KEYCLOAK_URL/admin/realms/master/users"

  # Create second user
  curl -H "Authorization: Bearer $KEYCLOAK_TOKEN" -X POST                     \
       -H "Content-Type: application/json"                                    \
       -d '{"username": "user2", "email": "user2@solo.io", "firstName": "Bob", "lastName": "Doe", "enabled": true, "attributes": {"group": "users"}, "credentials": [{"type": "password", "value": "password", "temporary": false}]}' \
       "$KEYCLOAK_URL/admin/realms/master/users"
}

function create_keycloak_secret {
  local _namespace=$1
  local _manifest="$MANIFESTS/secret.keycloak.${_namespace}.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/secret.keycloak.manifest.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  ### set_keycloak_token_client_and_secret # sets KEYCLOAK_TOKEN, KEYCLOAK_CLIENT, KEYCLOAK_SECRET, and KEYCLOAK_ID

  jinja2 -D namespace="$_namespace"                                           \
         -D secret="$KEYCLOAK_SECRET"                                         \
         "$_template"                                                         \
         "$_j2"                                                               \
  > "$_manifest"

  _apply_manifest "$_manifest"
}

function create_keycloak_extauth_auth_config {
  local _service_name _service_port _namespace
  while getopts "h:m:n:p:s:" opt; do
    # shellcheck disable=SC2220
    case $opt in
      m)
        _service_name=$OPTARG ;;
      s)
        _service_namespace=$OPTARG ;;
      h)
        _httproute_namespace=$OPTARG ;;
      n)
        _namespace=$OPTARG ;;
      p)
        _service_port=$OPTARG ;;
    esac
  done
  local _manifest="$MANIFESTS/auth_config.oauth.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES"/auth_config.oauth.manifest.yaml.j2
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  jinja2                                                                      \
         -D client_id="$KEYCLOAK_CLIENT"                                      \
         -D gateway_address="${_service_name}.${TLDN}"                        \
         -D httproute_name="${_service_name}-route"                           \
         -D httproute_namespace="${_httproute_namespace}"                     \
         -D keycloak_url="$KEYCLOAK_URL"                                      \
         -D service_namespace="$_service_namespace"                           \
         -D system_namespace="$GLOO_GATEWAY_NAMESPACE"                        \
         "$_template"                                                         \
         "$_j2"                                                               \
  > "$_manifest"

  _apply_manifest "$_manifest"
}
