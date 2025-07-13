# Media-Server
# 1 Installation du VPN - Wireguard 

#### Tableau d'adressage : 

|                  | Réseau interne | Réseau VPN     | Réseau admin |
|------------------|----------------|----------------| ------------ |
|Adresse du réseau | XXX.XXX.XXX.XXX| YYY.YYY.YYY.YYY| ZZZ.ZZZ.ZZZ.ZZZ |
| Jellyfin         |  :white_check_mark:  |  :white_check_mark:  | :white_check_mark: |
| Dowloader-stakc  |  :white_check_mark:  |  :white_check_mark:  | :white_check_mark: |
| NAS              |  :white_check_mark:  |  :x:  | :white_check_mark: |

Ayant constaté une difficulté à établir une communication via le Wireguard, sans configuration de notre part il est préférable utiliser un réseau interne réduit (en /29 par exemple) afin de lier les solutions au NAS/Samba.
Nous pouvons ainsi en profiter pour isoler le NAS de l'extérieur. 

### Installation de Wireguard - 

Récupérer les dossiers cliens et serveur, il est préférable de les zipper (.zip) pour un meilleur transfert.
Si jamais vous utiliser cette méthode, n'oubliez pas d'installer un outil pour gérer ce format de fichiers sur les machines :
```
dnf install zip -y 
```

#### 1. Côté serveur : 

Déplacer tous les fichiers dans le homedir de root : 
/!\ Les droits root sont requis pour exécuter les scripts /!\
```
sudo mv /server/* /root
```

Puis passage en utilisateur root : 
```
su -
```

Une fois dans le homedir de root : 
Inspecter le fichier de variables afin de modifier les IP que vous souhaiterez utiliser en fonction de votre tableau d'adressage.
```
vi wg_vars

declare -r ALLOWED_IPS='' #To change depending on the vpn subnet
declare -r SERVER_IP='' #To change depending on the intern subnet IP of the server.
```
Ces deux lignes vous intéresseront.

**Une fois les adresses affectées**

```
bash wg_srv_install.sh
```

Entrer une IP correspondante. 
Une fois le script consommé, la clé publique qui est à partager à vos clients s'affichera, copiez la. 

#### 2. Côté client : 

Déplacer tous les fichiers dans le homedir de root : 
/!\ Les droits root sont requis pour exécuter les scripts /!\
```
sudo mv /client/* /root
```

Puis passage en utilisateur root : 
```
su -
```

Inspecter le fichier de variables afin de modifier les IP que vous souhaiterez utiliser en fonction de votre tableau d'adressage.
```
vi wg_vars

declare -r ALLOWED_IPS='' #To change depending on the vpn subnet
declare -r SERVER_IP='' #To change depending on the intern subnet IP of the server.
```
Ces deux lignes vous intéresseront.

**Une fois les adresses affectées**

```
bash wg_new_client.sh {server_pub_key}
```

Suivre le prompt, entrer une IP correspondante dans le réseau VPN. 
A la fin, le script vous affichera la clée publique à partager à votre serveur. 

#### Côté Serveur : 

De nouveau du côté serveur  : 
```
bash wg_srv_add_peer.sh {client_pub_key} {client vpn subnet IP}
```

Rien de plus ne sera à faire ! 
Votre client et votre serveur sont connectés. 
Voici les commandes pour vérifier que tout se passe bien : 
```
wg #check the status of the interface
wg-quick up {interface-name} # start the interface
wg-quick up {interface-name} && wg-quick down {interface-name} #reload the interface
```

#### Ajout d'autres clients : 

Répéter le premier script client : 
```
bash wg_new_client.sh {server pub_key}
```
Répéter le second script serveur : 
```
bash wg_srv_add_peer.sh {client pub_key} {client vpn subnet IP}
```

____ 

Petit apparté si vous souhaitez que vos client puissent communiquer entre eux dans le LAN VPN, pour x ou y raison : 

#### Sur le serveur : 
```
firewall-cmd --add-masquerade #A éviter car trop permissif
```

Et ajouter ces règles dans le fichier de configuration de l'interface wireguard : 
```
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE;
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE;
```

# 2 Ajout du Reverse Proxy NGINX

Voici le fichier de configuration de NGINX : 
```
server {
    listen 80; #listening incomming traffic
    server_name {QBITTORRENT.YOUR_DOMAIN_NAME}; #domain name

    location /qbittorrent {
        proxy_pass http://{VPN DOWNLOADER IP}:8080; # local address where traffic should be forwarded to.
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80; #listening incomming traffic
    server_name {RADARR.YOUR_DOMAIN_NAME}; #domain name

    location /radarr {
        proxy_pass http://{VPN DOWNLOADER IP}:7878; # local address where traffic should be forwarded to.
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80; #listening incomming traffic
    server_name {JELLYFIN.YOUR_DOMAIN_NAME}; #domain name

    location /sonarr {
        proxy_pass http://{VPN DOWNLOADER IP}:8989; # local address where traffic should be forwarded to.
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80; #listening incomming traffic
    server_name {PROWLARR.YOUR_DOMAIN_NAME}; #domain name

    location /prowlarr {
        proxy_pass http://{VPN DOWLOADER IP}:9696; # local address where traffic should be forwarded to.
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80; #listening incomming traffic
    server_name {JELLYSEERR.YOUR_DOMAIN_NAME}; #domain name

    location /jellyseerr {
        proxy_pass http://{VPN DOWNLOADER IP}:5055; # local address where traffic should be forwarded to.
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80; #listening incomming traffic
    server_name {JELLYFIN.YOUR_DOMAIN_NAME}; #domain name

    location /jellyfin {

        proxy_pass http://{VPN JELLYFIN IP}:8096/jellyfin/;

        proxy_pass_request_headers on;

        proxy_set_header Host $host;

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;

        # Disable buffering when the nginx proxy gets very resource heavy upon streaming
        proxy_buffering off;
    }
}
```

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

