# akairos : infra web de référence sur OVH Public Cloud

Démo de formation : un réseau privé sur le vRack, un bastion, un load balancer
et N instances qui servent une petite page web. Tout est en Terraform : on
crée avant la séance, on détruit après, rien ne tourne entre deux formations.

```
                Internet
                   │
        ┌──────────┴───────────┐
        │                      │
   IP flottante           IP publique
  (load balancer)          (bastion)
        │                      │  SSH depuis admin_cidr seulement
┌───────┴──────────────────────┴───────────────────────────┐
│ vRack  ·  réseau privé akairos-net  ·  10.42.0.0/24      │
│                                                          │
│  akairos-lb ──HTTP──► akairos-app-1   10.42.0.10         │
│                └────► akairos-app-2   10.42.0.11  ...    │
│                                                          │
│  akairos-bastion 10.42.0.5 ──SSH──► app-*                │
│  akairos-gw (passerelle) : sortie Internet des app-*     │
└──────────────────────────────────────────────────────────┘
```

Schéma détaillé : [`docs/architecture.html`](docs/architecture.html) (à ouvrir dans un navigateur).

| Brique | Ressource | Rôle |
|---|---|---|
| Réseau privé | `akairos-net` (VLAN 42) + `akairos-subnet` | Relie les machines hors d'Internet |
| Passerelle | `akairos-gw` (modèle S) | Sortie Internet (SNAT) des instances privées, porte l'IP du LB |
| Bastion | `akairos-bastion` | Seul point d'entrée SSH |
| Load balancer | `akairos-lb` (Octavia, small) | HTTP:80 public, round robin, health check `/health` |
| Instances | `akairos-app-N` (d2-2, Debian 13) | nginx, page avec le nom de l'instance, **sans IP publique** |
| Pare-feu | security groups `akairos-bastion-sg`, `akairos-app-sg` | 22 depuis l'admin vers le bastion ; 80 depuis le sous-réseau et 22 depuis le bastion vers les app |

## Prérequis

- Terraform ≥ 1.9 (`brew install terraform`).
- Un projet Public Cloud **rattaché à un vRack** (fait une fois dans le manager OVH, hors Terraform).
- Une clé SSH : `~/.ssh/id_ed25519.pub` par défaut (`-var ssh_public_key_path=...`).
- Une clé API OVH :
  - **Antoine** : `source env.sh` charge la clé `claude-full` depuis `~/.config/infra/secrets.env` et détecte ton IP publique.
  - **Stagiaire** : créer une clé sur <https://eu.api.ovh.com/createToken/> avec les droits `GET`, `POST`, `PUT`, `DELETE` sur `/cloud/project/<id-projet>/*`, puis :
    ```bash
    export OVH_APPLICATION_KEY=...  OVH_APPLICATION_SECRET=...  OVH_CONSUMER_KEY=...
    export TF_VAR_service_name=<id-projet>
    source env.sh        # ne recharge rien si les OVH_* sont déjà là ; détecte l'IP
    ```

## Déroulé de la démo

```bash
source env.sh
terraform -chdir=infra init
terraform -chdir=infra apply                 # ~5 à 10 min (le LB est le plus long)
terraform -chdir=infra output
```

1. **Répartition de charge** : ouvrir `lb_url` dans le navigateur et recharger ; la couleur et le nom changent. En ligne de commande :
   ```bash
   scripts/verify.sh 20
   ```
2. **Accès par le bastion** : coller la sortie `terraform -chdir=infra output -raw ssh_config` dans `~/.ssh/config`, puis `ssh akairos-app-1`. Montrer qu'un accès direct est impossible : les instances n'ont aucune IP publique (`ssh debian@10.42.0.10` sans bastion ne mène nulle part).
3. **Passage à l'échelle** :
   ```bash
   terraform -chdir=infra apply -var instance_count=3
   scripts/verify.sh 30
   ```
   L'instance arrive dans le pool dès que son `/health` répond.
4. **Panne d'une instance** : `ssh akairos-app-1 sudo systemctl stop nginx`, relancer `scripts/verify.sh` : app-1 sort de la rotation en ~15 s. `sudo systemctl start nginx` : elle revient.
5. **Revenir à 2** : `terraform -chdir=infra apply -var instance_count=2` retire l'instance et son membre du pool.

## Fin de séance

```bash
terraform -chdir=infra destroy
python3 scripts/check-leftovers.py     # doit afficher « nothing left »
```

Le script liste tout ce qui commence par `akairos-` (et toute IP flottante orpheline) dans le projet, et vérifie que le bucket de sauvegardes `dna-backups-cronos` est toujours là.

## Bon à savoir

- **IP qui change** : si ta box a changé d'IP depuis le dernier `apply`, refaire `source env.sh` puis `apply` : la règle SSH du bastion se met à jour.
- **Coût** : facturation à l'heure, de l'ordre de quelques centimes par heure pour la configuration par défaut (3 petites instances, un LB small, une passerelle S, une IP flottante). Rien n'est facturé après `destroy`.
- **Le vRack n'est pas géré ici** : Terraform ne commande ni ne détache de vRack.
- **Load balancer** : il utilise la ressource `ovh_cloud_project_loadbalancer` (marquée dépréciée) parce que la nouvelle `ovh_cloud_loadbalancer` ne sait pas encore lui attacher une IP flottante (provider 2.24). Le reste utilise la nouvelle famille `ovh_cloud_*`.
- **Tests hors ligne** (aucune ressource créée) : `terraform -chdir=infra test`.
- **Épingler une image ou un gabarit** : `-var image_name="Debian 13 - UEFI"`, `-var image_id=...`, `-var flavor_name=b3-8`, `-var region=SBG5`.
