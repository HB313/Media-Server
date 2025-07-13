# Media-Server
# 1

# 2

# 3 Installation et configuration de la vm nas/Jellyfin/DL-stack
## A. Configuration et déploiement de la DL-stack
### 1. NAS
```
sudo dnf install -y dos2unix
chmod +x setup_nas.sh
dos2unix setup_nas.sh
sudo ./setup_nas.sh
sudo systemctl daemon-reload  # au besoin
```

⚠️ Note : le PUID et le PGID de l’utilisateur Samba défini ici doivent correspondre aux valeurs utilisées dans le docker-compose.yml de la DL-stack.



### 2. Jellyfin
```
sudo dnf install -y dos2unix
chmod +x setup_jellyfin.sh
dos2unix setup_jellyfin.sh
sudo ./setup_jellyfin.sh
```


### 3. DL-stack (Download Stack)

```
sudo dnf install -y dos2unix
chmod +x setup_DL.sh
dos2unix setup_DL.sh
sudo mkdir -p /srv/dl-stack/config/{qbittorrent,sonarr,radarr,prowlarr,jellyseerr} 
# il faut également mettre le fichier docker-compose.yml dans le dossier suivant /srv/dl-stack/
sudo ./setup_DL.sh

```
## B. 📡 Documentation Technique : Connexions entre les Services Media (Sonarr, Radarr, Prowlarr, Jellyfin, Jellyseerr, qBittorrent, NZBgeek)

## 🧭 Objectif

Décrire les **flux de communication** et **interconnexions** entre les services de type *media automation* et *gestion de téléchargements*, sans déployer ni orchestrer les conteneurs.

---

## 🔗 Vue d'ensemble des connexions

[NZBgeek] ---> [Prowlarr] ---> [Sonarr / Radarr] ---> [qBittorrent]
|
v
[Jellyseerr]
|
v
[Jellyfin]

### 1 Prowlarr <--> Sonarr / Radarr

### Rôle :
- Fournit les indexeurs à Sonarr et Radarr.

### Connexion :
- **Type** : HTTP interne
- **De Prowlarr vers Sonarr/Radarr** :
  - **API Endpoint** : `/api/v3/indexer`
  - **Authentification** : API Key générée côté Sonarr/Radarr
- **Sécurité recommandée** :
  - Restreindre les appels à l’IP locale de Prowlarr
  - Utiliser un pare-feu ou VPN local

---

### 2 Sonarr / Radarr <--> qBittorrent

### Rôle :
- Sonarr et Radarr envoient les tâches de téléchargement à qBittorrent.

### Connexion :
- **Type** : HTTP REST API
- **URL** : `http://<IP_QBIT>:8080`
- **Authentification** :
  - Nom d’utilisateur / mot de passe qBittorrent WebUI
- **Recommandations** :
  - Créer des **catégories** distinctes (`tv`, `movies`)
  - Définir des chemins de téléchargement par catégorie
  - Protéger l’interface Web par mot de passe fort

---

### 3 Jellyseerr <--> Sonarr / Radarr

### Rôle :
- Jellyseerr transmet les demandes de contenu aux gestionnaires (Sonarr pour les séries, Radarr pour les films).

### Connexion :
- **Type** : API REST
- **De Jellyseerr vers Sonarr/Radarr** :
  - **URL** : `http://<IP>:<PORT>`
  - **Authentification** : API Key respective de chaque service
- **Utilisation** :
  - Jellyseerr sélectionne automatiquement le profil de qualité, le chemin d’import, et lance la demande

---

### 4 Jellyseerr <--> Jellyfin

### Rôle :
- Jellyseerr synchronise les bibliothèques et utilisateurs avec Jellyfin.

### Connexion :
- **Type** : API REST
- **De Jellyseerr vers Jellyfin** :
  - **URL** : `http://<IP_JELLYFIN>:8096`
  - **Authentification** : Token API Jellyfin ou compte admin
- **Recommandation** :
  - Restreindre cette connexion au réseau local
  - Éviter les comptes admin partagés

---

## 5 Jellyfin <--- (lecture directe) --- Dossier média partagé

### Rôle :
- Jellyfin scanne les répertoires de médias où qBittorrent place les fichiers finalisés.

### Connexion :
- **Type** : Accès disque ou montage réseau (NFS, SMB ou volume local)
- **Exemple** :
  - `/mnt/media/movies`
  - `/mnt/media/tv`
- **Important** :
  - Les chemins doivent être **identiques** ou **reliés** entre qBittorrent, Radarr/Sonarr et Jellyfin
  - Assurez-vous des droits Unix corrects (`uid/gid`, ACL si nécessaire)

---

## 🔐 Sécurité réseau et services

### Recommandations globales :
- Restreindre tous les services à un réseau privé local ou VPN
- Protéger les interfaces Web par mot de passe fort
- Utiliser HTTPS via reverse proxy pour les services exposés (Traefik, Caddy, Nginx)

---

## 📌 Résumé des ports par défaut

| Service      | Port par défaut | Interface           |
|--------------|------------------|---------------------|
| Prowlarr     | 9696             | HTTP/API            |
| Sonarr       | 8989             | HTTP/API            |
| Radarr       | 7878             | HTTP/API            |
| qBittorrent  | 8080             | Web UI/API          |
| Jellyfin     | 8096             | Web UI/API          |
| Jellyseerr   | 5055             | Web UI/API          |

