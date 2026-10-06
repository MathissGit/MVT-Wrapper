# MVT Wrapper

Un petit outil en ligne de commande pour simplifier l'utilisation de **[MVT](https://github.com/mvt-project/mvt)** (Mobile Verification Toolkit), l'outil d'Amnesty International qui permet de rechercher des traces de logiciels espions sur un téléphone **iPhone** ou **Android** (via AndroidQF).

Le wrapper s'occupe de tout :

- installer les dépendances
- explorer une backup (acquise sur l'appareil ou fournie)
- vérifier si des **IoCs** (indicateurs de compromission) correspondent
- produire un **rapport** simple à lire
- garantir que la **preuve est préservée** pour un usage juridique

---

## Démarrage rapide

```bash
sudo ./install.sh     # une seule fois (instalation de dépendance)
sudo ./start.sh       # Script de lancement (menu principal)
```

`sudo ./start.sh` lance le scipt avec l'interface et le menu :

- **sans argument** → menu interactif (analyser, gérer les IoCs, installer),
- avec une **sous-commande** → usage d'une option directement (voir `./start.sh help`).

```
Menu principal
  1. Lancer une analyse
  2. Gérer les IoCs
  3. Vérifier / installer les dépendances
  4. Quitter
```

### Navigation des menus
La sélection des options se fait **avec les flèches du clavier** :

- **↑ / ↓** : déplacer la sélection
- **Entrée** : choisir l'option

## Sous-commandes

```bash
./start.sh analyse                                          # flux complet : IoCs + acquisition/analyse
./start.sh analyse --no-ioc-update                          # sans proposer la mise à jour des IoCs
./start.sh iocs                                             # menu de gestion des IoCs
./start.sh update-iocs                                      # met à jour repos git + IoCs officiels
./start.sh add mon-fichier.stix2                            # ajoute un fichier local
./start.sh add https://exemple.com/ioc.stix2                # ajoute une URL distante
./start.sh add-repo https://github.com/user/mes-iocs.git    # ajoute un dépôt
./start.sh list-iocs                                        # liste les IoCs chargés
./start.sh env-iocs                                         # affiche l'export MVT_STIX2 à copier
./start.sh purge                                            # supprime définitivement une affaire (dossier de preuves)
./start.sh purge 20260928                                   # purge l'affaire dont le nom contient « 20260928 »
./start.sh install                                          # lance install.sh
./start.sh help                                             # aide
```

`purge` est aussi accessible depuis le menu principal (« Purger les preuves
(destructif) », avant « Quitter »). Comme il supprime définitivement des
preuves, il demande **deux confirmations** : un oui/non, puis la saisie du
nom exact de l'affaire. Le mot de passe de scellement est exigé si les preuves
sont chiffrées.

## Gérer les IoCs (menu « Gérer les IoCs »)

Depuis le menu, vous pouvez :

1. **Mettre à jour** : synchronise vos **dépôts git** (`iocs/managed/`) et télécharge les **IoCs officiels de MVT** (`mvt download-iocs`).
2. **Ajouter un fichier local** (`.stix2`/`.json`) dans `iocs/custom/
3. **Ajouter une URL distante** pour télécharger un fichier d'IoCs.
4. **Ajouter un dépôt git** : il est enregistré dans `config.sh` (`IOC_REPOS`) et cloné dans `iocs/managed/`.
5. **Lister** les bundles disponibles.

Les dépôts git et les IoCs officiels sont **actualisés automatiquement** au début de chaque analyse.

> Tous les fichiers de `iocs/custom/` et `iocs/managed/` sont chargés par MVT via `MVT_STIX2`. Plus de dossiers que vous n'avez besoin : videz `iocs/custom/` ou retirez un dépôt de `IOC_REPOS`.

## Lancer une analyse

```bash
sudo ./start.sh
```
L'assistant vous guide :

1. **Mettre à jour les IoCs ?** (optionnel)
2. **Gérer / ajouter des IoCs ?** (optionnel)
3. **Nouvelle acquisition** (appareil connecté) **ou analyse d'un backup existant** ?
4. **Plateforme : iOS ou Android ?** (modèle de l'appareil détecté et affiché)
5. Pour une acquisition : le wrapper **attend l'appareil** 
6. Acquisition / analyse, puis **rapport** des menaces détectées.

---

## Ce que le wrapper fait pour vous

### Acquisition
- **iOS** : sauvegarde iTunes (`idevicebackup2`), recommande le backup **chiffré** (sinon des données clés manquent : appels, historique Safari…), **détecte le chiffrement réel de la backup créée** via `Manifest.plist` (`IsEncrypted`) — ni le statut device, ni une réponse utilisateur — puis demande le mot de passe **après** la sauvegarde et déchiffre automatiquement. Un backup non chiffré n'engendre plus de tentative de déchiffrement inutile.
- **Android** : acquisition avec l'outil **AndroidQF**.
- **Identification du terminal** : nom, modèle, iOS, build, série, IMEI… lus des **plists** de la backup (`Info.plist`, `Manifest.plist`) — renseignée même sans analyse MVT (mode préservation) et reprise dans le registre et le rapport.

### Préservation des preuves
Chaque analyse est rangée dans `evidence/CASE-AAAA-MMJJ-HHMMSS/` :

- un **manifeste SHA256** (`SHA256SUMS.txt`) scellant l'intégrité de tous les fichiers, généré en dernier (rien n'est écrit après : un `sha256sum -c` peut toujours tout vérifier) et **horodaté** en première ligne (générateur + machine),
- un manifeste de l'acquisition brute (`SHA256SUMS-acquisition.txt`) avant toute transformation,
- un **journal de traçabilité** (`chain_of_custody.txt`) qui couvre les 11 champs du registre : référence d'affaire, opérateur **+ structure**, **terminal identifié**, versions outils/composants, **version/date de la base d'IoCs**, opérations horodatées, empreintes SHA-256 **horodatées**, lieu/conservation (**hôte** + **modalité de scellement**), **référence du consentement écrit**, anomalies/incidents (échec MVT, quarantaines…),
- un journal des commandes exécutées (`audit.log`),
- le dossier passe en **lecture seule** à la fin (et immuable si lancé en `root`).

L'acquisition brute est préservée telle quelle.

### Rapport
Dans `evidence/CASE-.../results/` :

- `rapport.txt` : **mentions obligatoires** (identité et **structure** d'accueil de l'analyste, date/heure/terminal, **référence du consentement écrit** recueilli avant analyse, versions wrapper/MVT **et de chaque composant**, **machine d'analyse**, **base d'IoCs avec version/date**, **méthode + limites**, **niveau de confiance avec distinction spyware avéré / usage double légitime**), **identification du dispositif** (nom, marque, modèle, OS, build, IMEI, n° de série, numéro), **synthèse des menaces par niveau de gravité**, explication simple de chaque module, **état d'intégrité des preuves avec empreintes** — le tout horodaté et **scellé SHA256**,
- les fichiers JSON bruts de MVT (dont `*_detected.json`),
- `rapport.pdf` : version **imprimable** du rapport, générée par le wrapper en **pur Python (bibliothèque standard, aucune dépendance externe)** ; produite après le scellement et donc **hors manifeste**, à l'identique de `rapport.txt` (les encadrés y sont rendus en ASCII : `═`→`=`, `↑`→`^`…).

### Scellement des preuves (chiffrement AES-256)

En fin d'analyse, `SEAL_METHOD="encrypt"` (défaut) **chiffre les preuves en AES-256
(mot de passe, PBKDF2 ×100000)** puis supprime la version claire. Le dossier
`chain_of_custody.txt` est écrit **avant** le scellement, il est donc inclus dans
le contenu chiffré.

Deux modes, choisis automatiquement selon l'espace libre sur la destination :

| Mode | Produit | Espace nécessaire | Quand |
|---|---|---|---|
| **Archive** | `CASE-....aes256.tar.gz` | 1× la taille du dossier | la place suffit |
| **Flux** | `CASE-....aes256.d/` + `MANIFESTE.seal` | **le plus gros fichier seul** | place insuffisante |

Le mode flux chiffre **un fichier à la fois**, le relit pour vérifier
l'empreinte SHA256, puis détruit son clair. Le pic d'espace additionnel se
limite donc au plus gros fichier, ce qui permet de sceller un dossier bien plus
volumineux que l'espace disponible.

**Destination** : par défaut l'archive est écrite à côté du dossier de preuve.
Si ce volume est trop petit, choisissez un autre disque via
`./start.sh config` → « Destination de l'archive chiffrée ».

L'option propose la destination actuelle, le dossier de preuve, les volumes
montés détectés (`/media/<user>`, `/run/media/<user>`, avec leur **espace
libre** affiché), plus « Ouvrir le gestionnaire de fichiers » (fenêtre
`zenity`/`kdialog`) et une saisie manuelle. Après validation, le volume cible
et l'espace libre sont rappelés afin de vérifier qu'on n'écrit pas sur le
mauvais disque.

Garde-fous à la sélection :

- un chemin inexistant doit être **confirmé** avant création ;
- `~/` est développé, et un chemin relatif est refusé (`/absolu` attendu) ;
- un chemin sous `/media`, `/run/media` ou `/mnt` dont le volume n'est pas
  monté est **refusé** : le dossier serait sinon créé sur le disque interne
  et l'archive atterrirait au mauvais endroit ;
- un chemin existant qui n'est pas un dossier inscriptible est refusé ;
- en cas d'erreur, la destination enregistrée n'est **jamais** remise à zéro
  par surprise.

Si l'espace ne suffit **même pas** pour le mode flux, le scellement est refusé
avant toute écriture : les messages s'affichent **et** une ligne `INCIDENT`
est inscrite dans `chain_of_custody.txt` et `audit.log`. **Aucune preuve n'est
jamais détruite sans archive chiffrée vérifiée au préalable.**

Si le mode flux est **interrompu en cours de route** (panne, disque plein),
les fichiers déjà chiffrés et vérifiés ne sont pas supprimés : leur version
chiffrée est conservée et le message indique où elle se trouve, afin de
terminer le scellement plus tard sur les fichiers restants.

Déchiffrement manuel :

```bash
# mode archive
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in CASE-....aes256.tar.gz | tar xzf -
# mode flux (fichier par fichier)
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in CASE-....aes256.d/chemin/fichier -out fichier
```

> ⚠️ La mention **« Consentement »** est vérifiée **obligatoirement** avant toute analyse : sans consentement écrit recueilli (et confirmé), le wrapper refuse de continuer.

> ⚠️ Une « détection » ne signifie **pas automatiquement** que le téléphone est compromis : c'est un point de départ à confirmer par un analyste.

---

## Arborescence

```
mvt-wrapper/
├── install.sh            # installation complète
├── start.sh              # point d'entrée unique (menu + sous-commandes)
├── config.sh             # réglages (généré par install.sh)
├── .env                  # secrets : clé VirusTotal (généré par install.sh, gitignoré)
├── lib/
│   ├── common.sh         # fonctions partagées
│   └── jsonutils.py      # helper JSON partagé (recherche récursive de clé)
├── iocs/
│   ├── custom/           # IoCs ajouté à la main
│   └── managed/          # dépôts IoCs synchronisés automatiquement
├── evidence/             # preuves (acquisition + résultats + rapport, par affaire : CASE-.../results/)
```

## Réglages utiles (`config.sh`)

| Option | Rôle |
|---|---|
| `UPDATE_IOCS_BEFORE_ANALYSIS` | mise à jour des IoCs avant chaque analyse |
| `DOWNLOAD_OFFICIAL_IOCS` | télécharger les IoCs officiels de MVT |
| `IOC_REPOS` | liste des dépôts git d'IoCs synchronisés (ajout via le menu) |
| `ENABLE_VIRUSTOTAL` | vérification des APK Android sur VirusTotal — la clé se renseigne dans `.env`, jamais dans `config.sh` (voir ci-dessous) |
| `LOCK_EVIDENCE` | verrouillage des preuves en lecture seule |
| `ANALYST` | nom affiché dans les rapports |

### Clé VirusTotal (`MVT_VT_API_KEY`)

La clé se stocke dans le fichier **`.env`** à la racine du wrapper (généré par `install.sh`, `chmod 600`, ignoré par git).

1. Créez un compte gratuit sur <https://www.virustotal.com/gui/join-us> puis récupérez la clé sur <https://www.virustotal.com/gui/my-apikey>.
2. Enregistrez-la dans le menu : `./start.sh config` → « VirusTotal : définir la clé API » (elle est sauvegardée dans `.env` et utilisée dès la session en cours).

Vous pouvez aussi éditer `.env` à la main (`MVT_VT_API_KEY="votre-cle"`) puis relancer `./start.sh`. La valeur du `.env` prime sur un éventuel `export MVT_VT_API_KEY` du shell. VirusTotal ne s'utilise que si `ENABLE_VIRUSTOTAL="yes"` **et** la clé est définie.

## Vérifier le code

```bash
bash -n start.sh lib/common.sh install.sh config.sh   # vérification syntaxe bash
shellcheck -x start.sh lib/common.sh install.sh       # analyse statique (warnings/erreurs)
```

## Prérequis appareils

- **Android** : activez le **débogage USB** (Paramètres > Options développeur) et autorisez l'ordinateur.
- **iOS** : branchez l'iPhone, acceptez le **jumelage**, entrez le code PIN si demandé, et laissez l'appareil **déverrouillé** pendant la sauvegarde.

---

Basé sur la documentation officielle de [MVT](https://docs.mvt.re/).