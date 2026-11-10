# Infra de démo OVH Public Cloud : bastion + vRack + load balancer + compute

Date : 2026-11-10 — Auteur : Antoine PERRY (rédigé avec Claude)

## Intention

Antoine veut une **infrastructure de référence** du type « grosse infra » sur OVH Public Cloud, utilisée d'abord comme **démo en formation** : Antoine la monte et la montre, les stagiaires suivent ensuite. Elle doit illustrer les briques classiques d'une architecture web en production : réseau privé, point d'entrée SSH unique, répartition de charge, serveurs applicatifs sans IP publique.

## Objectifs

- Tout est décrit en **Terraform** : `terraform apply` avant la session, `terraform destroy` après, **rien ne tourne (ni ne coûte) entre deux formations**.
- Briques :
  - **vRack / réseau privé** : réseau privé OVH reliant toutes les machines, hors Internet.
  - **Bastion** : seule machine joignable en SSH depuis Internet ; passage obligé (ProxyJump) vers les instances.
  - **Load balancer** OVH Public Cloud (Octavia) : reçoit le HTTP public, répartit vers les instances.
  - **N instances compute**, sans IP publique, qui servent une app web simple.
- **App de démo** : une page qui affiche le nom de l'instance qui a répondu (hostname), son IP privée et de quoi constater la répartition en rechargeant la page.
- **Nombre d'instances paramétrable** (défaut 2), pour montrer en direct le passage à 3 (`terraform apply -var instance_count=3`) et l'ajout automatique dans le pool du load balancer.

## Non-objectifs

- Pas de nom de domaine ni de HTTPS : accès HTTP sur l'IP publique du load balancer.
- Pas de base de données, pas de stockage partagé.
- Pas d'environnements stagiaires pour l'instant (une infra, celle d'Antoine).
- Pas d'autoscaling, de monitoring ni de CI.

## Anti-objectifs (échec même si « ça marche »)

- Instances compute joignables directement depuis Internet (IP publique ou SSH ouvert).
- Ressources oubliées qui continuent à facturer après `terraform destroy`.
- Secrets OVH écrits en clair dans le dépôt ou dans le state commité.
- Toucher à quoi que ce soit d'autre dans le projet D&A Engineering (bucket `dna-backups-cronos` et ses utilisateurs S3 notamment).

## Contraintes

- **Projet Public Cloud « D&A Engineering »** `120a120c626c48d28773c56e42bce375` (compte `pa639772-ovh`), choix d'Antoine. Ce projet contient déjà le bucket de sauvegardes `dna-backups-cronos` : ne rien modifier hors des ressources créées par ce Terraform.
- Identifiants API OVH : clé `claude-full` (`OVH_FULL_APP_KEY`, `OVH_FULL_APP_SECRET`, `OVH_FULL_CONSUMER_KEY`) dans `~/.config/infra/secrets.env`, restreinte à l'IP de la box d'Antoine et à hermes-vps. Charger via `set -a; . ~/.config/infra/secrets.env; set +a`, puis les exposer au provider sous les noms qu'il attend. Jamais de valeur dans le dépôt.
- **vRack** : le projet est déjà rattaché au vRack `pn-1380461` (constaté par l'API le 2026-11-10, aucun réseau privé existant). Ce rattachement est un **prérequis conservé hors Terraform** : Terraform ne commande ni ne détache de vRack, il crée seulement le réseau privé, le sous-réseau et la gateway, qui sont détruits au `destroy`.
- Clé SSH : `~/.ssh/id_ed25519.pub`.
- **Poste d'exécution** : Terraform et SSH sont lancés depuis le Mac d'Antoine, chez lui (IP autorisée par la clé `claude-full`). Terraform 1.16.6 est déjà installé (Homebrew). `admin_cidr` est détecté automatiquement (IP publique courante en /32) et reste surchargeable.
- **Portabilité (choix de Claude)** : ID de projet, région et clé SSH sont des variables. Les identifiants passent par les variables d'environnement standard du provider (`OVH_ENDPOINT`, `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY`), alimentées sur le poste d'Antoine depuis `OVH_FULL_*` par un petit script `env.sh` (non commité si ça contient des valeurs ; il ne fait que remapper). Le README indique comment un stagiaire crée sa propre clé API sur un compte vierge.
- Coût : les plus petits gabarits disponibles dans la région retenue.
- Code et commentaires en anglais ; README en français (support de formation).

## Décisions de conception

Décidé par Antoine :
- Terraform ; projet D&A Engineering ; app simple qui affiche le nom de l'instance ; région GRA ou SBG, petits gabarits, nombre d'instances en variable (défaut 2), HTTP sur l'IP du LB.

Choix de Claude (validés en bloc par Antoine, à corriger s'il le souhaite) :
- Provider **`ovh/ovh`** en priorité (réseau privé, gateway, load balancer, instances) ; repli sur `terraform-provider-openstack` pour ce que le provider OVH ne couvre pas bien, avec un utilisateur OpenStack créé par Terraform lui-même.
- Région par défaut : **GRA11** (variable), à confirmer selon la disponibilité de Octavia et du réseau privé.
- App : **nginx installé par cloud-init**, page HTML générée au boot avec hostname, IP privée et date de démarrage ; un endpoint `/health` pour le health check du LB.
- Bastion : petite instance avec IP publique, SSH par clé uniquement, sécurité groupe/pare-feu limitant le 22 (variable `admin_cidr`, défaut = IP courante d'Antoine).
- Les instances compute sortent sur Internet (apt) via une **gateway** OVH (SNAT), sans IP publique.
- State Terraform **local** (non commité, `.gitignore`) : c'est une démo à un seul opérateur.
- Sorties Terraform : IP du LB (URL de démo), IP du bastion, bloc `~/.ssh/config` prêt à coller (ProxyJump).

## Laissé au constructeur

- Structure des fichiers Terraform (modules ou non), noms des ressources (préfixe commun `akairos-` pour les repérer et les nettoyer).
- Gabarit exact (d2-2, b3-8…) selon disponibilité dans la région.
- Plage d'adressage privé et VLAN.
- Script de vérification (`curl` en boucle sur le LB montrant l'alternance des noms d'instance).
- Un `README.md` déroulé de démo : prérequis, `apply`, démonstrations (répartition, SSH via bastion, passage à 3 instances, arrêt d'une instance et retrait du pool), `destroy` et contrôle qu'il ne reste rien.

## Vérification attendue

1. `terraform apply` réussit depuis zéro.
2. `curl` répété sur l'IP du LB montre au moins deux noms d'instance différents.
3. `ssh` vers une instance passe par le bastion ; une connexion directe est impossible (pas d'IP publique).
4. `-var instance_count=3` ajoute une instance visible dans les réponses.
5. `terraform destroy` supprime tout ; un listing API du projet ne montre plus aucune ressource `akairos-*` et le bucket `dna-backups-cronos` est intact.
