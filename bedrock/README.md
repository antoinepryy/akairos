# Bedrock sur Kubernetes

La démo WordPress Bedrock du dépôt `docker-swarm`, portée sur le Kubernetes
managé d'OVH : même site, même bucket de médias, mais décrite en charts Helm et
déployée par Argo CD depuis ce dépôt public.

```
Internet ─▶ load balancer OVH ─▶ Traefik ×2 ─▶ WordPress ×3 ─┬─▶ bedrock-db-primary ─▶ Galera ×3 (un par nœud, volume chacun)
              (créé par Kubernetes)  (HTTPS, cert-manager)     ├─▶ Redis (cache objet)
                                                              └─▶ S3 OVH (médias, préfixe k8s/)
```

| Swarm (`docker-swarm`) | Kubernetes (ici) |
|---|---|
| `./swarm create`, scripts API OVH | `terraform apply` (module `k8s-stack`) |
| `./swarm bedrock deploy` après un commit | `git push` : Argo CD applique en ~30 s |
| Traefik sur swarm-1 seulement | Traefik ×2 derrière un load balancer OVH |
| galera-1/2/3 + ProxySQL écrits à la main | mariadb-operator : amorçage, reprise, bascule du nœud d'écriture |
| images construites sur chaque nœud | image construite par GitHub Actions, registre `ghcr.io` |
| secrets Swarm | Secret Kubernetes créé par `scripts/bedrock-secrets.sh` (jamais dans git) |

## Ce qui est où

```
bedrock/                   Terraform : cluster (module k8s-stack), Traefik, cert-manager, mariadb-operator
apps/bedrock/              chart Helm suivi par Argo CD : WordPress, Redis, Galera, Ingress, job d'installation
images/bedrock-site/       projet Bedrock et son image (non root, port 8080)
.github/workflows/bedrock-image.yml   construit et publie l'image à chaque modification de images/bedrock-site
scripts/bedrock-secrets.sh crée le Secret bedrock-env dans le cluster
```

Le cluster s'appelle `bedrock-k8s` (VLAN 44, 10.44.0.0/24) : il peut tourner en
même temps que le niveau 2 (`akairos-k8s`, VLAN 43).

## Monter la démo (~15 min)

```bash
source env.sh
cd bedrock && terraform init && terraform apply && cd ..
eval "$(scripts/k8s-kubeconfig.sh bedrock)"    # exporte KUBECONFIG
scripts/bedrock-secrets.sh                     # Secret bedrock-env
kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; echo
```

Au premier passage, `host` est vide dans `apps/bedrock/values.yaml` : le site
répond en HTTP sur l'IP du load balancer, sans installation. Ensuite :

1. Mettre `host: bedrock.<ip-avec-tirets>.sslip.io` dans `apps/bedrock/values.yaml`, commit, push.
2. Argo CD crée l'Issuer, cert-manager obtient le certificat Let's Encrypt, puis
   le job `wordpress-install` installe WordPress et active Redis et S3.
3. `https://bedrock.<ip-avec-tirets>.sslip.io/wp/wp-admin/`, utilisateur `demo`,
   mot de passe `BEDROCK_WP_ADMIN_PASSWORD` de secrets.env.

Suivre : `kubectl -n bedrock get pods,mariadb,certificate,job`. Interface Argo CD :
`kubectl -n argocd port-forward svc/argocd-server 8080:80`, mot de passe
`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.

## Déroulé de la démo

| Notion | Commande | À montrer |
|---|---|---|
| GitOps | changer `wordpress.replicas` (3 → 5), push | Argo CD crée deux pods ; `kubectl scale` à la main est annulé (selfHeal) |
| Répartition | `curl -sI https://<host>/ \| grep x-served-by` en boucle | le pod change à chaque requête |
| Mise à jour progressive | nouvelle image (`wordpress.image`), push | un pod de plus d'abord, jamais sous 3 (`maxUnavailable: 0`) |
| Panne du nœud d'écriture | `kubectl -n bedrock delete pod bedrock-db-0` | `kubectl -n bedrock get mariadb -w` : PRIMARY passe sur un autre pod, le site continue |
| Perte d'un nœud | `kubectl drain <nœud> --ignore-daemonsets --delete-emptydir-data` | les PDB laissent partir un pod à la fois ; `kubectl uncordon` ensuite |
| Isolation | `kubectl run t --rm -it --image=busybox -- nc -zv redis.bedrock 6379` | refusé : seuls WordPress et le job parlent à Redis |
| Règles du projet | un `Role` ou un pod root ajouté au chart | Argo CD et Pod Security refusent |

## Nouvelle image

Modifier `images/bedrock-site`, push : le workflow `bedrock-image` publie
`ghcr.io/antoinepryy/akairos-bedrock-site:<sha court>`. Mettre ce tag dans
`wordpress.image`, push. Le paquet doit être public (réglage du paquet sur
GitHub) : le cluster le tire sans identifiants.

## Arrêter (et ne plus payer)

```bash
cd bedrock && terraform destroy && cd .. && TF_VAR_prefix=bedrock python3 scripts/check-leftovers.py
```

L'ordre est imposé par Terraform : l'Application d'abord (l'opérateur supprime
Galera et ses volumes), le garde-fou attend que les Services et volumes du
namespace aient disparu chez OVH, puis Traefik et l'attente de son load
balancer, puis les opérateurs, Argo CD et le cluster. `check-leftovers` cherche
aussi les volumes `pvc-*`.

Coût indicatif tant que c'est allumé : 3 × d2-8 (~0,11 € HT/h), un load
balancer small, la passerelle et 6 petits volumes. Plan de contrôle gratuit (Free).

## Limites (démo, pas production)

- Aucune sauvegarde de la base. mariadb-operator sait faire (`Backup`,
  `PhysicalBackup` vers S3) : c'est la première chose à ajouter pour un client.
- Volumes supprimés avec l'application (`pvcRetentionPolicy: Delete`) : voulu pour
  la démo, à passer en `Retain` en production.
- Secrets créés à la main par script. En production : dépôt privé et
  External Secrets ou Sealed Secrets.
- Base neuve : le contenu du site Swarm n'est pas repris (les médias sont
  sous un autre préfixe du même bucket).
- Le cluster local de Docker Desktop (kind) n'applique pas les NetworkPolicies :
  elles ne se vérifient que chez OVH.
