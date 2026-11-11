# Changelog

Versions of the modules (`modules/vm-stack`, `modules/k8s-stack`) that client
repositories pin with `?ref=vX.Y.Z`.

## v1.0.1 (2026-11-11)

Fixes from an audit (Codex, read-only), no change to the created resources.

- Client template: `client.tfvars` was ignored by git, so a repository
  generated from v1.0.0 lacked it. `new-client.sh` now takes the template from
  the tag itself (`git archive`), never from the working tree.
- Client template: `kube_version` is pinned in `client.tfvars` (1.35).
- `k8s-stack`: the destroy guard stores the script's content in the state, not
  an absolute path of the machine that ran `apply`. kubectl calls time out.
- `env.sh` (demo and client): reads only the needed secrets from
  `secrets.env`, instead of exporting all of them to terraform.
- `new-client.sh`: literal replacement (names with `&`, `|` or `\`), works with
  GNU and BSD tools, validates region, repository and name.
- `check-leftovers.py`: an empty or malformed API answer and a hung request
  are errors (exit 2), never "nothing left".
- kubeconfig scripts: written atomically, mode 600 even over an old file.
- Offline tests of the scripts: `python3 -m unittest discover -s tests`.

## v1.0.0 (2026-11-10)

- `vm-stack`: vRack network, bastion, Octavia load balancer (legacy LB without
  listener, v2 listener/pool/members), N private instances. Validated live at SBG5.
- `k8s-stack`: Managed Kubernetes on the vRack (free or standard plan, optional
  private nodes), anti-affinity node pool, API restricted to the admin CIDR and
  the cluster gateway, Argo CD with one Application (public repo, or private
  with a deploy key), destroy guard for the Kubernetes-made load balancer.
  Free plan validated live at SBG5; standard plan, private nodes and private
  repository not yet run live.
