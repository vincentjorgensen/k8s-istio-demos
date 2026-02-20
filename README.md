# k8s-istio-demos

Common functions for manipulating Istio clusters, Gloo Platform, and Solo.io
builds

# Requirements

```bash
brew install jinja2 kubectl
```

Version 1.17.2 of Helm required until [this
issue](https://github.com/helm/helm/issues/30738)  is fixed.

```bash
brew uninstall helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=v3.17.2 bash
```

Some commands require `istioctl` (though I've tried my best to limit them).

```bash
mkdir $HOME/.istioctl/bin
PATH=$HOME/.istioctl/bin:$PATH

istio_ver=1.28
istio_ver_min=1.28.4

curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$istio_ver_min sh -

cp istio-${istio_ver_min}/bin/istioctl $HOME/.istioctl/bin/istioctl-${istio_ver}
```

# Usage

```bash
source ./functions.sh
```
