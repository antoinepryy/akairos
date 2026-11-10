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

## Bon à savoir

- **IP qui change** : si ta box a changé d'IP depuis le dernier `apply`, refaire `source env.sh` puis `apply` : seule la règle SSH du security group change.
- **Coût** (catalogue OVH, HT) : ≈ 0,05 €/h pour la configuration par défaut (3 × d2-2 à 0,0104, LB small 0,0083, passerelle S 0,0028, 2 IP flottantes à 0,0027). Toute heure entamée est due. Rien n'est facturé après `destroy`.
- **Le vRack n'est pas géré ici** : Terraform ne commande ni ne détache de vRack.
- **Région SBG5** par défaut : le 10/11/2026, GRA11 n'avait plus de capacité d2 (« No valid host was found », à la création comme au redimensionnement). Si ça arrive, changer de région (`-var region=GRA9`) plutôt que d'insister.
- **Load balancer en deux temps** : la nouvelle ressource `ovh_cloud_loadbalancer` ne peut pas recevoir d'IP publique (OVH refuse l'action IAM `loadbalancer/usePublicIP … missing X-Ovh-Authentication-Detail-Id`, avec une clé API comme avec un compte de service). Le LB lui-même est donc créé par l'ancienne ressource `ovh_cloud_project_loadbalancer` (marquée dépréciée), **sans listener**, avec une IP flottante gérée par Terraform. Le listener, le pool et les membres sont des ressources `ovh_cloud_*` séparées, branchées sur ce même LB : changer `instance_count` ne touche que les membres. Une attente de 60 s sépare les deux, car l'API v2 ne voit le LB qu'un peu après sa création (404 sinon).
- **IP privées** attribuées par OVH (DHCP) : l'API exige qu'une IP fixe soit dans la plage DHCP, ce qui exposerait à des collisions. Terraform relit les adresses après création.
- **Image figée** : une instance garde l'image de sa création, même si OVH publie un Debian 13 plus récent (sinon un simple `apply` réinstallerait les machines en pleine démo). Pour changer : `terraform -chdir=infra apply -replace='ovh_cloud_instance.app[0]'`.
- **Clé SSH posée par cloud-init**, pas comme « clé OVH » : supprimer une clé v2 laissait une copie dans le projet, et les créations simultanées se gênaient (409). Changer de clé réinstalle les instances : aucune ancienne clé ne reste autorisée.
- **Tests hors ligne** (aucune ressource créée) : `terraform -chdir=infra test`.
- **Épingler une image ou un gabarit** : `-var image_name="Debian 13 - UEFI"`, `-var image_id=...`, `-var flavor_name=d2-4`, `-var region=GRA9`.
