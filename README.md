# kubernetes-askema

Lightweight (citation needed) tool for creating k8s clusters runnng demo infrastructures

Examples:
- Gateway API (Traefik, KGateway, Gloo Gateway V2)
- Istio (Ambient or Sidecar), OSS or Enterprise
- Cert Manager
- Cloud (AWS, AKS, maybe GCP)

For debugging, I use my custom [helloworld
microservice](https://github.com/vincentjorgensen/helloworld-rust-microservice)
and [netshoot](https://github.com/nicolaka/netshoot)

# Requirements

```bash
brew install jinja2 kubectl helm jq yq
```

## istioctl
Some commands require `istioctl` (though I've tried my best to limit them).

```bash
mkdir $HOME/.istioctl/bin
PATH=$HOME/.istioctl/bin:$PATH

istio_ver=1.29
istio_ver_min=1.29.0

curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$istio_ver_min sh -

cp istio-${istio_ver_min}/bin/istioctl $HOME/.istioctl/bin/istioctl-${istio_ver}
```

# Usage

A running kubernetes cluster is required. For local development, I use k3d on
Docker Desktop (or Rancher Desktop). See my other repo
[k3d-calico-metallb](https://github.com/vincentjorgensen/k3d-calico-metallb)
for how I instantiate clusters locally.

Assuming there is cluster named `cluster1`:
```bash
source ./ksa.sh

ksa_play c1_traefik
```

will deploy a Traefik ingress gateway in Gateway API to the cluster with the
sample `helloworld` app behind it. To test if the gateway works, try:
```bash
INGRESS_GATEWAY_IP=kubectl --namespace ingress-gateways                        \
                           get svc traefik                                     \
                           -ojsonpath='{.status.loadBalancer.ingress[].ip}'
curl -H 'Host: helloworld.example.com' $INGRESS_GATEWAY_IP
```
```text
Hello, world!
```

