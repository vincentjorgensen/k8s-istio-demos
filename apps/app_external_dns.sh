#!/usr/bin/env bash
function app_init_external_dns {
  if $EXTERNAL_DNS_ENABLED; then
    echo '# '"$0"
      $ITER_MC_1 exec_external_dns_for_pihole
  fi
}

function exec_external_dns_for_pihole {
  local _manifest="$MANIFESTS/helm.external-dns.${KSA_CLUSTER}.yaml"
  local _template="$TEMPLATES/external-dns/helm.values.yaml.j2"
  local _de_manifest="$MANIFESTS/external-dns-${KSA_CLUSTER}/deployment.external-dns.patch.yaml"
  local _de_template="$TEMPLATES"/external-dns/deployment.patch.yaml
  local _kustomize_renderer="$MANIFESTS/external-dns-${KSA_CLUSTER}/kustomize.sh"
  local _kustomization_template="$TEMPLATES"/external-dns/pihole.kustomization.yaml.j2
  local _kustomization="$MANIFESTS/external-dns-${KSA_CLUSTER}/kustomization.yaml"
  local _j2="$MANIFESTS"/jinja2_globals."$KSA_CLUSTER".yaml

  local _post_renderer_plugin_template="$TEMPLATES"/helm.post-renderer.plugin.yaml.j2
  local _post_renderer_plugin="$MANIFESTS/external-dns-${KSA_CLUSTER}"

  [[ ! -e $(dirname "$_kustomize_renderer") ]] && mkdir "$(dirname "$_kustomize_renderer")"

  jinja2 -D plugin_name="external-dns-${KSA_CLUSTER}"                          \
         -D manifest_dir="$MANIFESTS"                                          \
       "$_post_renderer_plugin_template"                                       \
    > "$_post_renderer_plugin/plugin.yaml"

  local _pihole_server_address
  _pihole_server_address=$(docker inspect pihole | jq -r '.[].NetworkSettings.Networks."'"$DOCKER_NETWORK"'".IPAddress')

  $DRY_RUN kubectl create secret generic pihole-password                       \
  --context "$KSA_CONTEXT"                                                     \
  --namespace "$KUBE_SYSTEM_NAMESPACE"                                         \
  --from-literal EXTERNAL_DNS_PIHOLE_PASSWORD="$(yq -r '.services.pihole.environment.FTLCONF_webserver_api_password' "$K3D_DIR"/docker-compose.yaml)"

  jinja2 -D pihole_server_address="$_pihole_server_address"                    \
       "$_template"                                                            \
       "$_j2"                                                                  \
    > "$_manifest"

  cp "$_de_template" "$_de_manifest"

  jinja2                                                                       \
       "$_kustomization_template"                                              \
       "$_j2"                                                                  \
  > "$_kustomization"

  cp "$TEMPLATES"/kustomize.sh "$_kustomize_renderer"

  if is_create_mode; then
    if helm plugin list|grep -q external-dns-"${KSA_CLUSTER}"; then
      $DRY_RUN helm plugin uninstall external-dns-"${KSA_CLUSTER}"
    fi
    $DRY_RUN helm plugin install "$_post_renderer_plugin"

    $DRY_RUN helm upgrade -i external-dns external-dns/external-dns            \
    --version "$EXTERNAL_DNS_VER"                                              \
    --kube-context="$KSA_CONTEXT"                                              \
    --namespace "$KUBE_SYSTEM_NAMESPACE"                                       \
    --values "$_manifest"                                                      \
    --post-renderer "external-dns-${KSA_CLUSTER}"                              \
    --wait
  fi
}
