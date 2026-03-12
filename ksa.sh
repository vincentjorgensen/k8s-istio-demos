#!/usr/bin/env bash
source "$(dirname "$0")"/globals.sh
for app in "$(dirname "$0")"/apps/*; do
  # shellcheck source=/dev/null
  source "$app"
done

KSA_DECK=(
  ksa_init

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

function ksa_play {
  [[ -n $1 ]] && UTAG=$1
  local infra=${1:-$UTAG}

  # shellcheck source=/dev/null
  source "$(dirname "$0")/infras/infra_${infra}.sh"
  export KSA_MODE=apply # create
  for exe in "${KSA_DECK[@]}"; do
    echo '#'"$exe"
    eval "$exe"
  done
}

function ksa_rew {
  infra=$1

  # shellcheck source=/dev/null
  source "$(dirname "$0")/infras/infra_${infra}.sh"
  export KSA_MODE=delete
  # shellcheck disable=SC2296
  for exe in "${(Oa)KSA_DECK[@]}"; do
    echo '#'"$exe"
    eval "$exe"
  done
}

function ksa_dry_run {
  [[ -n $1 ]] && UTAG=$1
  local infra=${1:-$UTAG}

  # shellcheck source=/dev/null
  source "$(dirname "$0")/infras/infra_${infra}.sh"
  export DRY_RUN="echo"
  for exe in "${KSA_DECK[@]}"; do
    echo '#'"$exe"
    eval "$exe"
  done
  export DRY_RUN=""
}

function ksa_zip {
  [[ -n $1 ]] && UTAG=$1
  local infra=${1:-$UTAG}
  MANIFESTS="$(dirname "$0")"/manifests/$UTAG

  ksa_dry_run "$infra" | tee -a "run_${UTAG}.sh"
  # Strip license keys
  _strip_license_keys "$MANIFESTS"
  zip "$REPLAYS/${UTAG}.zip" "run_${UTAG}.sh" "$MANIFESTS"/*
  echo '# '"$REPLAYS/${UTAG}.zip"
}

function ksa_dry_run_e {
  local _exec="$*"
  DRY_RUN='echo' eval "$*"
}

function ksa_rew_e {
  local _exec="$*"
  KSA_MODE='delete' eval "$*"
}

function ksa_play_e {
  local _exec="$*"
  KSA_MODE='apply' eval "$*"
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
  for _cluster in $(env|ggrep KSA_CLUSTER|sed -e 's/KSA_CLUSTER\(.*\)=.*/\1/'); do
    export KSA_CLUSTER KSA_CONTEXT KSA_NETWORK
    KSA_CLUSTER=$(eval echo '$'KSA_CLUSTER"${_cluster}")
    KSA_CONTEXT=$(eval echo '$'KSA_CONTEXT"${_cluster}")
    KSA_NETWORK=$(eval echo '$'KSA_NETWORK"${_cluster}")

    for _exe in "$@"; do
      eval "$_exe"
    done
  done
}

function _iter_mc_1 {
    export KSA_CLUSTER KSA_CONTEXT KSA_NETWORK
    local _cluster=1
    KSA_CLUSTER=$(eval echo '$'KSA_CLUSTER"${_cluster}")
    KSA_CONTEXT=$(eval echo '$'KSA_CONTEXT"${_cluster}")
    KSA_NETWORK=$(eval echo '$'KSA_NETWORK"${_cluster}")

    for _exe in "$@"; do
      eval "$_exe"
    done
}
