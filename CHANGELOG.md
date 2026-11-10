# Changelog

Versions of the modules (`modules/vm-stack`, `modules/k8s-stack`) that client
repositories pin with `?ref=vX.Y.Z`.

## v1.0.0 (2026-11-10)

- `vm-stack`: vRack network, bastion, Octavia load balancer (legacy LB without
  listener, v2 listener/pool/members), N private instances. Validated live at SBG5.
- `k8s-stack`: Managed Kubernetes on the vRack (free or standard plan, optional
  private nodes), anti-affinity node pool, API restricted to the admin CIDR and
  the cluster gateway, Argo CD with one Application (public repo, or private
  with a deploy key), destroy guard for the Kubernetes-made load balancer.
  Free plan validated live at SBG5; standard plan, private nodes and private
  repository not yet run live.
