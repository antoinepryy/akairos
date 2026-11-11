# Changelog

Versions of the modules (`modules/vm-stack`, `modules/k8s-stack`) that client
repositories pin with `?ref=vX.Y.Z`.

## v1.1.0 (2026-11-11)

Cluster hardening (audit follow-up). Checked on a local kind cluster, then live
at OVH SBG5 on 2026-11-11 (free plan, 2 x d2-4): created in 10 min 50 in one
apply; the OVH load balancer reaches the pods through the network policy (30/30,
3 pods); ClusterRoleBinding, deployment to kube-system and root pod refused;
Argo CD UI times out from another namespace, answers from argocd and through
port-forward; self-heal; IP-change recovery; destroy in 2 min 40, nothing left.

- `k8s-stack`: the app has its own Argo CD project (its repository, its
  namespace, namespaced app kinds only: `app_resource_kinds`) instead of
  `default`. A commit can no longer create a ClusterRoleBinding or deploy
  elsewhere. The project is a separate release, removed after the Application.
- `k8s-stack`: the app's namespace enforces Pod Security `restricted`.
- `k8s-stack`: network policies. Default deny in `argocd`, argocd-server
  reachable from its own namespace only (the chart's policy allowed any source).
- `k8s-stack`: the destroy guard also waits for the Application to be fully
  deleted (its finalizer removes everything it deployed), not only the Service.
- `apps/web`: unprivileged nginx on 8080 pinned by digest, read-only root
  filesystem, no capability, no service account token, default-deny network
  policy, values schema (at least 2 replicas).
- Docs: recovery when the operator's IP changed (`-refresh=false -target`),
  IAM scope of the client's service account. Found live: with the API refusing
  the operator's IP, the Helm provider reads the releases as gone and a normal
  plan proposes to re-create Argo CD and the apps; it must not be applied.
- Breaking for apps deployed with the module: images running as root are
  refused in the app's namespace, and only the kinds of `app_resource_kinds`
  are synced.

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
