# akairos : infra web de référence sur OVH Public Cloud

Démo de formation : un réseau privé sur le vRack, un bastion, un load balancer
et N instances qui servent une petite page web. Tout est en Terraform : on
crée avant la séance, on détruit après, rien ne tourne entre deux formations.

```
                Internet
                   │
        ┌──────────┴───────────┐
        │                      │
   IP flottante           IP flottante
  (load balancer)          (bastion)
        │                      │  SSH depuis admin_cidr seulement
┌───────┴──────────────────────┴───────────────────────────┐
│ vRack  ·  réseau privé akairos-net  ·  10.42.0.0/24      │
│                                                          │
│  akairos-lb ──HTTP──► akairos-app-1   (IP privée DHCP)   │
│                └────► akairos-app-2   ...                │
│                                                          │
│  akairos-bastion (IP privée DHCP) ──SSH──► app-*          │
│  akairos-gw (passerelle) : SNAT sortant + IP flottantes  │
└──────────────────────────────────────────────────────────┘
```

Schéma détaillé : [`docs/architecture.html`](docs/architecture.html) (à ouvrir dans un navigateur).

| Brique | Ressource | Rôle |
|---|---|---|
| Réseau privé | `akairos-net` (VLAN 42) + `akairos-subnet` | Relie les machines hors d'Internet |
| Passerelle | `akairos-gw` (modèle S) | Sortie Internet (SNAT) des instances privées, porte les IP flottantes |
| Bastion | `akairos-bastion` + IP flottante | Seul point d'entrée SSH, une seule carte réseau (privée) |
| Load balancer | `akairos-lb` (Octavia, small) + IP flottante | HTTP:80 public, round robin, health check `/health` |
| Instances | `akairos-app-N` (d2-2, Debian 13) | nginx, page avec le nom de l'instance, **sans IP publique** |
| Pare-feu | security groups `akairos-bastion-sg`, `akairos-app-sg` | 22 depuis l'admin vers le bastion ; 80 depuis le sous-réseau et 22 depuis le bastion vers les app |

## Organisation du dépôt

| Dossier | Contenu |
|---|---|
| `modules/vm-stack` | Module du niveau 1 (VM, bastion, LB), sans valeur propre à un projet |
| `modules/k8s-stack` | Module du niveau 2 (Kubernetes managé, Argo CD) |
| `infra/`, `k8s/` | La démo de formation : ces modules avec les valeurs D&A Engineering |
| `apps/web` | Chart de l'app de démo, suivi par Argo CD |
| `templates/client` | Modèle de dépôt pour un client (voir « Répliquer pour un client ») |

## Prérequis

- Terraform ≥ 1.9 (`brew install terraform`).
- Un projet Public Cloud **rattaché à un vRack** (fait une fois dans le manager OVH, hors Terraform).
- Une clé SSH : `~/.ssh/id_ed25519.pub` par défaut (`-var ssh_public_key_path=...`).
- Un **compte de service OVH** (OAuth2), pas une clé API classique : certaines actions de l'API v2 vérifient une identité IAM qu'une clé classique ne porte pas.
  - **Antoine** : `source env.sh` charge le compte de service `akairos-terraform` (politique IAM limitée au projet D&A Engineering) depuis `~/.config/infra/secrets.env` et détecte ton IP publique.
  - **Stagiaire** :
    1. Avec une clé API classique ou depuis la console API (<https://eu.api.ovh.com/console/>), créer le compte : `POST /me/api/oauth2/client` avec `{"name":"terraform","description":"formation","flow":"CLIENT_CREDENTIALS","callbackUrls":[]}`. Noter `clientId` et `clientSecret` (affiché une seule fois).
    2. Lire son identité : `GET /me/api/oauth2/client/<clientId>` → champ `identity`.
    3. Lui donner les droits sur le projet : `POST /v2/iam/policy` avec `{"name":"terraform","identities":["<identity>"],"resources":[{"urn":"urn:v1:eu:resource:publicCloudProject:<id-projet>"}],"permissions":{"allow":[{"action":"publicCloudProject:apiovh:*"}]}}`.
    4. Puis :
       ```bash
       export OVH_CLIENT_ID=...  OVH_CLIENT_SECRET=...
       export TF_VAR_service_name=<id-projet>   # et TF_VAR_region si autre que SBG5
       source env.sh        # ne recharge rien si OVH_CLIENT_ID est déjà là ; détecte l'IP
       ```

## Déroulé de la démo

```bash
source env.sh
terraform -chdir=infra init
terraform -chdir=infra apply                 # ~8 à 10 min (le LB prend ~3 min à lui seul)
terraform -chdir=infra output
```

1. **Répartition de charge** : ouvrir `lb_url` dans le navigateur et recharger ; la couleur et le nom changent. En ligne de commande :
   ```bash
   scripts/verify.sh 20
   ```
2. **Accès par le bastion** : coller la sortie `terraform -chdir=infra output -raw ssh_config` dans `~/.ssh/config`, puis `ssh akairos-app-1`. Montrer qu'un accès direct est impossible : les instances n'ont aucune IP publique (`ssh debian@<IP privée de app_private_ips>` sans bastion finit en timeout).
3. **Passage à l'échelle** :
   ```bash
   terraform -chdir=infra apply -var instance_count=3
   scripts/verify.sh 30 3
   ```
   Seul un membre est ajouté au pool : le load balancer ne bouge pas (mesuré : 135 requêtes sur 135 en 200 pendant l'opération, une par seconde). La nouvelle instance n'entre dans la rotation qu'une fois son `/health` OK.
4. **Panne d'une instance** : `ssh akairos-app-1 sudo systemctl stop nginx`, relancer `scripts/verify.sh` : app-1 sort de la rotation sans erreur côté client (mesuré : 0 requête en échec). `sudo systemctl start nginx` : elle revient.
5. **Revenir à 2** : `terraform -chdir=infra apply -var instance_count=2` retire l'instance et son membre du pool, sans coupure.

## Fin de séance

```bash
terraform -chdir=infra destroy               # avec le même -var instance_count que le dernier apply
python3 scripts/check-leftovers.py     # doit afficher « nothing left »
```

Le script liste tout ce qui commence par `akairos-` (et toute IP flottante orpheline) dans le projet et la région de `TF_VAR_region`. Il échoue (code 2) si une seule liste n'a pas pu être lue : un contrôle incomplet n'est jamais annoncé comme propre. Sur le Mac d'Antoine, il vérifie aussi que le bucket de sauvegardes `dna-backups-cronos` est toujours là. Si tu as changé de région ou de préfixe, exporte les mêmes `TF_VAR_region` / `TF_VAR_prefix` avant `source env.sh`.

## Niveau 2 : Kubernetes, Helm et Argo CD

Même vRack, mais l'orchestration passe à Kubernetes. Ce que le niveau 1 fait à la main (load balancer, ajout d'instances, mise à jour), le cluster le fait seul, et git devient la source de vérité. Les deux niveaux ont chacun leur réseau (VLAN 43, `10.43.0.0/24`) et peuvent tourner ensemble.

| Brique | Ressource | Rôle |
|---|---|---|
| Réseau | `akairos-k8s-net` + sous-réseau + passerelle `akairos-k8s-gw` | Réseau privé des nœuds ; sortie Internet et IP flottantes |
| Cluster | `akairos-k8s` (Managed Kubernetes, plan Free) | Plan de contrôle gratuit, API ouverte à `admin_cidr` seulement (l'équivalent du bastion) |
| Nœuds | `akairos-k8s-workers` : 2 × d2-4, anti-affinité | Chaque nœud sur un hôte physique différent |
| Argo CD | chart `argo-cd`, installé par Terraform (provider Helm) | Synchronise le cluster avec git toutes les 30 s |
| App | chart [`apps/web`](apps/web) : 3 pods nginx, `Service LoadBalancer` | La page affiche le pod, le nœud et la version ; le load balancer est créé par Kubernetes |

Prérequis en plus du niveau 1 : `kubectl` (`brew install kubectl`). Un stagiaire forke le dépôt (public) et passe `-var git_repo_url=https://github.com/<lui>/akairos.git`.

```bash
source env.sh
terraform -chdir=k8s init
terraform -chdir=k8s apply                    # ~15 min (cluster ~8 min, nœuds ~5 min)
eval "$(scripts/k8s-kubeconfig.sh)"           # exporte KUBECONFIG
export URL="$(scripts/k8s-url.sh)"            # attend l'IP du load balancer
kubectl -n web get pods -o wide
```

1. **Répartition** : `scripts/verify.sh 30 3` (le nom du pod et du nœud changent).
   Mesuré le 10/11/2026 : 30/30 en 200 sur les 3 pods.
2. **Autoréparation** : `kubectl -n web delete pod <un pod>` ; un autre le remplace en quelques secondes. `kubectl -n web scale deploy web --replicas=1` est annulé par Argo CD : c'est git qui décide.
3. **Mise à l'échelle par git** : `replicas: 5` dans [`apps/web/values.yaml`](apps/web/values.yaml), commit, push ; 30 s plus tard, 5 pods.
4. **Mise à jour sans coupure** : dans un terminal, `scripts/verify.sh 300 1` ; dans l'autre, `version: v2` et `color: "#16a34a"`, commit, push. Les pods sont remplacés un par un (un en plus d'abord, sonde `/health`, 5 s de délai avant l'arrêt) : aucune requête en échec, la page passe au vert (mesuré : 251 requêtes sur 251 en 200, deux par seconde).
5. **Retour arrière** : `git revert HEAD && git push`.
6. **Perte d'un nœud** : `kubectl drain <nœud> --ignore-daemonsets --delete-emptydir-data` ; les pods migrent sur l'autre nœud, un seul à la fois (PodDisruptionBudget). `kubectl uncordon <nœud>` ensuite. Mesuré avec le retour arrière : 293 requêtes sur 293 en 200.
7. **Interface Argo CD** (facultatif) : `kubectl -n argocd port-forward svc/argocd-server 8080:80`, puis <http://localhost:8080>, utilisateur `admin`, mot de passe : `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.

Fin de séance :

```bash
terraform -chdir=k8s destroy
python3 scripts/check-leftovers.py           # « nothing left »
```

**Piège géré** : le load balancer de l'app est créé par Kubernetes, Terraform ne le connaît pas. Si le cluster disparaissait avant lui, il resterait chez OVH, facturé. Au `destroy`, Terraform supprime donc d'abord l'Application Argo CD (qui supprime le Service), attend que le Service ait disparu (il ne disparaît qu'une fois le load balancer supprimé chez OVH), puis seulement Argo CD et le cluster. `check-leftovers` contrôle aussi les clusters et les load balancers `kube_service_*` (OVH nomme ainsi le LB d'un Service et ignore l'annotation de nom).

**Restriction d'IP de l'API** : OVH la refuse tant qu'un pool de nœuds est en cours d'installation (400 `IntegrityError`) ; Terraform la pose donc après les nœuds. Elle autorise ton IP et celle de la passerelle du cluster : Argo CD, dans le cluster, sort par cette passerelle.

**Coût** (HT) : ≈ 0,06 €/h (2 × d2-4 à 0,0206, LB small 0,0083, passerelle S 0,0028, IP flottante 0,0027). Le plan Free du cluster est gratuit ; le plan Standard coûterait 0,09 €/h de plus.

**Tests hors ligne** : `terraform -chdir=modules/k8s-stack test`, `helm lint apps/web` et `python3 -m unittest discover -s tests` (garde-fou de destruction avec un faux `kubectl`).

## Répliquer pour un client

Chaque client a **son propre dépôt** (privé), **dans son compte OVH** : projet, vRack, factures et state Terraform sont chez lui. Le dépôt appelle le module `k8s-stack` d'akairos **épinglé à une version** (tag git), si bien qu'une évolution d'akairos ne touche aucun client sans qu'on le décide.

```bash
scripts/new-client.sh ~/IdeaProjects/acme-platform "ACME" acme <id-projet> SBG5 acme-corp/platform
```

Le script prend `templates/client` **dans le dernier tag** d'akairos (pas dans la copie de travail : le dépôt généré correspond à la version du module qu'il épingle), remplit les valeurs et initialise git. La suite (compte de service, politique IAM, bucket du state, clé de déploiement, secrets, `plan`, `apply`) est dans le README du dépôt généré. Le profil par défaut est celui de la production : plan Standard, nœuds sans IP publique, 3 × b3-8.

Publier une version du module : mettre à jour `CHANGELOG.md`, puis `git tag vX.Y.Z && git push --tags`.

## Bon à savoir

- **IP qui change** : si ta box a changé d'IP depuis le dernier `apply`, refaire `source env.sh` puis `apply` : seule la règle SSH du security group change.
- **Coût** (catalogue OVH, HT) : ≈ 0,05 €/h pour la configuration par défaut (3 × d2-2 à 0,0104, LB small 0,0083, passerelle S 0,0028, 2 IP flottantes à 0,0027). Toute heure entamée est due. Rien n'est facturé après `destroy`.
- **Le vRack n'est pas géré ici** : Terraform ne commande ni ne détache de vRack.
- **Région SBG5** par défaut : le 10/11/2026, GRA11 n'avait plus de capacité d2 (« No valid host was found », à la création comme au redimensionnement). Si ça arrive, changer de région (`-var region=GRA9`) plutôt que d'insister.
- **Load balancer en deux temps** : la nouvelle ressource `ovh_cloud_loadbalancer` ne peut pas recevoir d'IP publique (OVH refuse l'action IAM `loadbalancer/usePublicIP … missing X-Ovh-Authentication-Detail-Id`, avec une clé API comme avec un compte de service). Le LB lui-même est donc créé par l'ancienne ressource `ovh_cloud_project_loadbalancer` (marquée dépréciée), **sans listener**, avec une IP flottante gérée par Terraform. Le listener, le pool et les membres sont des ressources `ovh_cloud_*` séparées, branchées sur ce même LB : changer `instance_count` ne touche que les membres. Une attente de 60 s sépare les deux, car l'API v2 ne voit le LB qu'un peu après sa création (404 sinon).
- **IP privées** attribuées par OVH (DHCP) : l'API exige qu'une IP fixe soit dans la plage DHCP, ce qui exposerait à des collisions. Terraform relit les adresses après création.
- **Image figée** : une instance garde l'image de sa création, même si OVH publie un Debian 13 plus récent (sinon un simple `apply` réinstallerait les machines en pleine démo). Pour changer : `terraform -chdir=infra apply -replace='ovh_cloud_instance.app[0]'`.
- **Clé SSH posée par cloud-init**, pas comme « clé OVH » : supprimer une clé v2 laissait une copie dans le projet, et les créations simultanées se gênaient (409). Changer de clé réinstalle les instances : aucune ancienne clé ne reste autorisée.
- **Tests hors ligne** (aucune ressource créée) : `terraform -chdir=modules/vm-stack test`, `terraform -chdir=modules/k8s-stack test` et `python3 -m unittest discover -s tests` (scripts : inventaire OVH simulé, garde-fou de destruction, génération d'un dépôt client depuis un clone neuf).
- **Épingler une image ou un gabarit** : `-var image_name="Debian 13 - UEFI"`, `-var image_id=...`, `-var flavor_name=d2-4`, `-var region=GRA9`.
