# Plateforme __CLIENT__

Kubernetes managé OVH sur le vRack de __CLIENT__, avec Argo CD qui déploie les applications de ce dépôt (`apps/`). Le socle vient du module [`k8s-stack`](https://github.com/antoinepryy/akairos/tree/__MODULE_REF__/modules/k8s-stack) d'akairos, épinglé à `__MODULE_REF__`.

Tout est chez le client : projet Public Cloud, vRack, factures OVH et state Terraform. Ce dépôt ne contient aucun secret.

## 1. Entrée du client (une fois)

À faire dans le compte OVH du client, par lui ou par nous avec une délégation :

1. **Projet Public Cloud** rattaché à un **vRack** (manager OVH). Noter l'id du projet.
2. **Compte de service** : `POST /me/api/oauth2/client` avec `{"name":"terraform-__PREFIX__","description":"plateforme","flow":"CLIENT_CREDENTIALS","callbackUrls":[]}` ; noter `clientId` et `clientSecret` (affiché une seule fois). Lire son identité : `GET /me/api/oauth2/client/<clientId>`.
3. **Politique IAM** limitée au projet : `POST /v2/iam/policy` avec `{"name":"terraform-__PREFIX__","identities":["<identity>"],"resources":[{"urn":"urn:v1:eu:resource:publicCloudProject:<id-projet>"}],"permissions":{"allow":[{"action":"publicCloudProject:apiovh:*"}]}}`.
4. **Bucket du state** : dans le projet, un utilisateur S3 et un bucket `__PREFIX__-tfstate` (région `__S3_REGION__`), versionné. C'est la seule copie de l'état de la plateforme.
5. **Dépôt git privé** pour ce dossier, avec une **clé de déploiement en lecture seule** (`ssh-keygen -t ed25519 -f ~/.ssh/__PREFIX__-deploy -N ""`, la clé publique dans les « Deploy keys » du dépôt).
6. **Secrets** sur le poste de l'opérateur, dans `~/.config/infra/secrets.env` (chmod 600), jamais dans le dépôt :
   ```
   __ENV__CLIENT_ID=...
   __ENV__CLIENT_SECRET=...
   __ENV__S3_ACCESS_KEY=...
   __ENV__S3_SECRET_KEY=...
   __ENV__DEPLOY_KEY_FILE=~/.ssh/__PREFIX__-deploy
   ```

## 2. Déploiement

```bash
source env.sh
terraform init -backend-config=backend.hcl
terraform plan -var-file=client.tfvars -out=platform.tfplan    # relire : rien d'inattendu
terraform apply platform.tfplan                                 # ~15 min
eval "$(scripts/kubeconfig.sh)"
kubectl get nodes
kubectl -n argocd get applications                              # Synced / Healthy
kubectl -n web get svc web                                      # EXTERNAL-IP = adresse du load balancer
```

Contrôle : `python3 <akairos>/scripts/check-leftovers.py` liste ce qui porte le préfixe `__PREFIX__-` (env.sh exporte projet, région et préfixe). Après un `apply`, il doit lister la plateforme ; après un `destroy`, « nothing left ».

## 3. Exploitation

- **Déployer** : modifier `apps/`, commit, push. Argo CD applique en 30 s environ. Un changement fait à la main dans le cluster est annulé : git fait foi.
- **Ajouter une app** : un chart par dossier dans `apps/`. Pour une deuxième Application, dupliquer le module ou étendre `app_*` (une Application par module à ce jour).
- **Monter de version le socle** : changer `?ref=` dans `main.tf` (lire le CHANGELOG d'akairos), `terraform init -upgrade`, puis `plan`.
- **Version de Kubernetes** : figée par `kube_version` dans `client.tfvars`, pour qu'une recréation donne la même. La monter exprès (versions proposées : `GET /cloud/project/{id}/capabilities/kube/versions`), une mineure à la fois, puis `plan`.
- **Accès à l'API Kubernetes** : seulement depuis `admin_cidr` (IP de l'opérateur, détectée par env.sh) et la passerelle de la plateforme. Changement d'IP : `source env.sh`, puis `plan` / `apply`.

## 4. Avant la mise en production (selon ce que le client héberge)

Le socle ne fournit pas encore : HTTPS (ingress et cert-manager, il faut un nom de domaine), supervision et alertes, sauvegardes (base de données, Velero), secrets applicatifs (External Secrets ou Sealed Secrets), politique de mises à jour du cluster. À décider avec le client, et à ajouter dans `apps/`.

## 5. Fin de contrat

`terraform destroy -var-file=client.tfvars` attend que le load balancer créé par Kubernetes ait disparu avant de supprimer le cluster (sinon il resterait facturé). Puis `check-leftovers.py`, puis : supprimer la politique IAM, le compte de service et la clé de déploiement. Le bucket du state se supprime en dernier, à la main.
