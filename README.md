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
./start.sh install                                          # lance install.sh
./start.sh help                                             # aide
```

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
- **iOS** : sauvegarde iTunes (`idevicebackup2`), recommande le backup **chiffré** (sinon des données clés manquent : appels, historique Safari…), déchiffre automatiquement si un mot de passe est donné.
- **Android** : acquisition avec l'outil **AndroidQF**.

### Préservation des preuves
Chaque analyse est rangée dans `evidence/CASE-AAAA-MMJJ-HHMMSS/` :

- un **manifeste SHA256** (`SHA256SUMS.txt`) scellant l'intégrité de tous les fichiers, généré en dernier (rien n'est écrit après : un `sha256sum -c` peut toujours tout vérifier),
- un manifeste de l'acquisition brute (`SHA256SUMS-acquisition.txt`) avant toute transformation,
- un **journal de traçabilité** (`chain_of_custody.txt`) qui note qui fait quoi et quand,
- un journal des commandes exécutées (`audit.log`),
- le dossier passe en **lecture seule** à la fin (et immuable si lancé en `root`).

L'acquisition brute est préservée telle quelle.

### Rapport
Dans `reports/CASE-.../` :

- `rapport.txt` : **mentions obligatoires** (identité et **structure** d'accueil de l'analyste, date/heure/terminal, **consentement écrit** signé et recueilli avant analyse, versions wrapper/MVT, méthode + limites, IoCs utilisés), **identification du dispositif** (nom, marque, modèle, OS, build, IMEI, n° de série, numéro), **synthèse des menaces par niveau de gravité**, explication simple de chaque module, état d'intégrité des preuves — le tout horodaté et **scellé SHA256**,
- les fichiers JSON bruts de MVT (dont `*_detected.json`).

> ⚠️ La mention **« Consentement »** est vérifiée **obligatoirement** avant toute analyse : sans consentement écrit recueilli (et confirmé), le wrapper refuse de continuer.

> ⚠️ Une « détection » ne signifie **pas automatiquement** que le téléphone est compromis : c'est un point de départ à confirmer par un analyste.

---

## Arborescence

```
mvt-wrapper/
├── install.sh            # installation complète
├── start.sh              # point d'entrée unique (menu + sous-commandes)
├── config.sh             # réglages
├── lib/common.sh         # fonctions partagées
├── iocs/
│   ├── custom/           # IoCs ajouté à la main
│   └── managed/          # dépôts IoCs synchronisés automatiquement
├── evidence/             # preuves
└── reports/              # rapports + résultats JSON
```

## Réglages utiles (`config.sh`)

| Option | Rôle |
|---|---|
| `UPDATE_IOCS_BEFORE_ANALYSIS` | mise à jour des IoCs avant chaque analyse |
| `DOWNLOAD_OFFICIAL_IOCS` | télécharger les IoCs officiels de MVT |
| `IOC_REPOS` | liste des dépôts git d'IoCs synchronisés (ajout via le menu) |
| `MVT_VT_API_KEY` / `ENABLE_VIRUSTOTAL` | vérification des APK Android sur VirusTotal |
| `LOCK_EVIDENCE` | verrouillage des preuves en lecture seule |
| `ANALYST` | nom affiché dans les rapports |

## Prérequis appareils

- **Android** : activez le **débogage USB** (Paramètres > Options développeur) et autorisez l'ordinateur.
- **iOS** : branchez l'iPhone, acceptez le **jumelage**, entrez le code PIN si demandé, et laissez l'appareil **déverrouillé** pendant la sauvegarde.

---

Basé sur la documentation officielle de [MVT](https://docs.mvt.re/).