#!/usr/bin/env bash
source "$(dirname "$0")"/globals.sh
for app in "$(dirname "$0")"/apps/*; do
  # shellcheck source=/dev/null
  source "$app"
done

GSI_DECK=(
  gsi_init

  app_init_namespaces

  # Infrastructure apps
  app_choose_infra

  # Gateway controllers
  app_choose_gateway

  # Test applications
  app_choose_apps

  # Ingresses and Egresses
  app_choose_ingresses
)

function play_gsi {
  [[ -n $1 ]] && UTAG=$1
  local infra=${1:-$UTAG}

  # shellcheck source=/dev/null
  source "$(dirname "$0")/infras/infra_${infra}.sh"
  export GSI_MODE=apply # create
  for exe in "${GSI_DECK[@]}"; do
    echo '#'"$exe"
    eval "$exe"
  done
}

function rew_gsi {
  infra=$1

  # shellcheck source=/dev/null
  source "$(dirname "$0")/infras/infra_${infra}.sh"
  export GSI_MODE=delete
  # shellcheck disable=SC2296
  for exe in "${(Oa)GSI_DECK[@]}"; do
    echo '#'"$exe"
    eval "$exe"
  done
}

function dry_run_gsi {
  [[ -n $1 ]] && UTAG=$1
  local infra=${1:-$UTAG}

  # shellcheck source=/dev/null
  source "$(dirname "$0")/infras/infra_${infra}.sh"
  export DRY_RUN="echo"
  for exe in "${GSI_DECK[@]}"; do
    echo '#'"$exe"
    eval "$exe"
  done
  export DRY_RUN=""
}

function zip_gsi {
  [[ -n $1 ]] && UTAG=$1
  local infra=${1:-$UTAG}
  MANIFESTS="$(dirname "$0")"/manifests/$UTAG

  dry_run_gsi "$infra" | tee -a "run_${UTAG}.sh"
  # Strip license keys
  _strip_license_keys "$MANIFESTS"
  zip "$REPLAYS/${UTAG}.zip" "run_${UTAG}.sh" "$MANIFESTS"/*
  echo '# '"$REPLAYS/${UTAG}.zip"
}

function dry_run_e {
  local _exec="$*"
  DRY_RUN='echo' eval "$*"
}

function rew_e {
  local _exec="$*"
  GSI_MODE='delete' eval "$*"
}

function play_e {
  local _exec="$*"
  GSI_MODE='apply' eval "$*"
}

function _strip_license_keys {
  local _manifests=$1
  local _file
  pushd "$_manifests" || return
  for _file in $(ggrep -Isli 'license_*key' ./*); do
    sed 's/\(^.*license_*key:\) .*/\1 REDACTED/I' "$_file" > "${_file}".redacted
    rm "$_file"
    mv "${_file}".redacted "$_file"
  done
  popd || return
}

function _iter_mc {
  local _cluster
  for _cluster in $(env|ggrep GSI_CLUSTER|sed -e 's/GSI_CLUSTER\(.*\)=.*/\1/'); do
    export GSI_CLUSTER GSI_CONTEXT GSI_NETWORK
    GSI_CLUSTER=$(eval echo '$'GSI_CLUSTER"${_cluster}")
    GSI_CONTEXT=$(eval echo '$'GSI_CONTEXT"${_cluster}")
    GSI_NETWORK=$(eval echo '$'GSI_NETWORK"${_cluster}")

    for _exe in "$@"; do
      eval "$_exe"
    done
  done
}

function _iter_mc_1 {
    export GSI_CLUSTER GSI_CONTEXT GSI_NETWORK
    local _cluster=1
    GSI_CLUSTER=$(eval echo '$'GSI_CLUSTER"${_cluster}")
    GSI_CONTEXT=$(eval echo '$'GSI_CONTEXT"${_cluster}")
    GSI_NETWORK=$(eval echo '$'GSI_NETWORK"${_cluster}")

    for _exe in "$@"; do
      eval "$_exe"
    done
}
