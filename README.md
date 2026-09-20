# Lab — Administration sécurisée Linux

Ce dépôt contient le script permettant de préparer automatiquement une machine virtuelle **Ubuntu Server 26.04 LTS** utilisée dans les travaux pratiques du module :

**Administration sécurisée Linux / Windows**

Le script prépare volontairement un serveur présentant plusieurs configurations à **analyser, auditer et améliorer** pendant les TP.

> ⚠️ Cet environnement est exclusivement destiné à la formation.
> Certaines configurations sont volontairement moins sécurisées afin de permettre leur analyse pendant les exercices.
> **Ne pas utiliser ce script sur une machine de production ou exposée directement à Internet.**

---

## Objectifs

Ce laboratoire est utilisé principalement pour deux travaux pratiques :

### TP 1 — Fondamentaux de l'administration sécurisée

Vous devrez notamment :

* identifier les utilisateurs et groupes ;
* analyser les comptes privilégiés ;
* identifier les comptes techniques ;
* analyser les permissions ;
* vérifier la configuration `sudo` ;
* analyser les politiques de mots de passe ;
* examiner les connexions utilisateur ;
* comprendre le principe du moindre privilège.

### TP 2 — Hardening des systèmes

Vous devrez notamment :

* identifier les services actifs ;
* identifier les ports ouverts ;
* analyser la configuration SSH ;
* identifier les services inutiles ;
* vérifier les mises à jour ;
* analyser les paramètres réseau ;
* utiliser UFW ;
* comprendre Netfilter / nftables ;
* configurer Fail2ban ;
* consulter les journaux système ;
* appliquer des mesures de durcissement.

---

# Prérequis

Vous devez disposer de :

* une machine virtuelle **Ubuntu Server 26.04 LTS** ;
* un compte utilisateur disposant de `sudo` ;
* un accès Internet depuis la VM pour l'installation des packages ;
* une connexion réseau en mode **NAT** ou **Host-only** recommandée.

Vérifiez votre version Ubuntu :

```bash
cat /etc/os-release
```

Vous pouvez également utiliser :

```bash
hostnamectl
```

---

# Récupération du dépôt

Clonez le dépôt GitHub fourni par l'enseignant :

```bash
git clone <URL_DU_DEPOT>
```

Entrez ensuite dans le répertoire :

```bash
cd <NOM_DU_DEPOT>
```

Vérifiez la présence du script :

```bash
ls -l
```

Vous devez notamment trouver :

```text
prepare-lab.sh
```

---

# Préparation du script

Donnez les droits d'exécution au script :

```bash
chmod +x prepare-lab.sh
```

Lancez ensuite la préparation du laboratoire :

```bash
sudo ./prepare-lab.sh
```

Le script va automatiquement :

* installer les packages nécessaires ;
* créer les comptes utilisés pendant les exercices ;
* installer et configurer OpenSSH ;
* installer nginx ;
* créer un service pédagogique supplémentaire ;
* installer UFW ;
* installer nftables ;
* installer Fail2ban ;
* configurer plusieurs paramètres utilisés pendant les TP ;
* générer des informations nécessaires au laboratoire.

---

# Vérification du laboratoire

À la fin de l'installation, vérifiez que le serveur fonctionne correctement.

## Informations système

```bash
hostnamectl
```

```bash
cat /etc/os-release
```

---

## Vérification des comptes

```bash
getent passwd
```

Vous devriez notamment retrouver plusieurs comptes créés pour le TP.

Pour afficher les groupes disposant de privilèges administrateur :

```bash
getent group sudo
```

---

## Vérification des services

```bash
systemctl --type=service --state=running
```

---

## Vérification des ports

```bash
sudo ss -tulpn
```

Plusieurs ports pourront être visibles.

Cela est **normal** dans le contexte du laboratoire.

L'objectif du TP sera justement de déterminer :

* pourquoi ces ports sont ouverts ;
* quel service les utilise ;
* s'ils sont réellement nécessaires.

---

# Comptes du laboratoire

Le script crée plusieurs profils permettant d'étudier la gestion des utilisateurs et des privilèges.

Par exemple :

| Compte      | Rôle pédagogique                             |
| ----------- | -------------------------------------------- |
| `adminlab`  | Compte disposant de privilèges élevés        |
| `dev01`     | Utilisateur disposant de certains privilèges |
| `dev02`     | Utilisateur standard                         |
| `olduser`   | Exemple de compte potentiellement inutilisé  |
| `backupsvc` | Exemple de compte technique                  |

> Ne supprimez ou ne modifiez pas ces comptes avant que l'exercice correspondant ne vous le demande.

---

# Mots de passe du laboratoire

Les mots de passe des comptes de laboratoire sont générés automatiquement.

Ils sont enregistrés dans :

```text
/root/training-lab-credentials.txt
```

Pour les afficher :

```bash
sudo cat /root/training-lab-credentials.txt
```

> Ces mots de passe sont uniquement destinés au laboratoire.

---

# Informations destinées au laboratoire

Un résumé de la configuration pédagogique est disponible dans :

```text
/etc/training-lab-info.txt
```

Vous pouvez le consulter avec :

```bash
cat /etc/training-lab-info.txt
```

Selon les instructions de l'enseignant, il pourra vous être demandé de **ne pas consulter immédiatement ce fichier**, afin de rechercher vous-même les anomalies du système.

---

# Commandes utiles pour le TP 1

## Identifier votre utilisateur

```bash
whoami
```

```bash
id
```

---

## Afficher les utilisateurs

```bash
getent passwd
```

---

## Afficher les groupes

```bash
getent group
```

---

## Afficher les membres du groupe sudo

```bash
getent group sudo
```

---

## Vérifier vos permissions sudo

```bash
sudo -l
```

---

## Vérifier les informations d'un utilisateur

```bash
id dev01
```

---

## Vérifier la politique d'expiration

```bash
sudo chage -l dev01
```

---

## Afficher les connexions

```bash
who
```

```bash
last
```

```bash
lastlog
```

---

# Commandes utiles pour le TP 2

## Lister les services actifs

```bash
systemctl --type=service --state=running
```

---

## Lister les services activés au démarrage

```bash
systemctl list-unit-files --type=service --state=enabled
```

---

## Afficher les ports ouverts

```bash
sudo ss -tulpn
```

---

## Vérifier la configuration SSH effective

```bash
sudo sshd -T
```

Quelques paramètres particulièrement intéressants :

```bash
sudo sshd -T | grep permitrootlogin
```

```bash
sudo sshd -T | grep passwordauthentication
```

```bash
sudo sshd -T | grep pubkeyauthentication
```

```bash
sudo sshd -T | grep maxauthtries
```

---

# Pare-feu UFW

Vérifier l'état d'UFW :

```bash
sudo ufw status verbose
```

Afficher les règles :

```bash
sudo ufw status numbered
```

> N'activez ou ne modifiez pas le firewall avant que l'exercice ne vous le demande.

---

# Netfilter / nftables

Afficher les règles nftables :

```bash
sudo nft list ruleset
```

Afficher les tables :

```bash
sudo nft list tables
```

Netfilter est le mécanisme de filtrage intégré au noyau Linux.

`nftables` permet de configurer directement les règles Netfilter alors que **UFW fournit une interface simplifiée**.

---

# Fail2ban

Vérifier le service :

```bash
sudo systemctl status fail2ban
```

Afficher son état :

```bash
sudo fail2ban-client status
```

Après configuration du jail SSH :

```bash
sudo fail2ban-client status sshd
```

Fail2ban permet notamment de détecter les échecs répétés d'authentification et de bannir temporairement certaines adresses IP.

---

# Paramètres réseau

Afficher le routage IPv4 :

```bash
sysctl net.ipv4.ip_forward
```

Afficher les paramètres IPv4 principaux :

```bash
sysctl -a | grep net.ipv4
```

---

# Journaux système

Afficher les événements récents :

```bash
journalctl --since today
```

Afficher les warnings :

```bash
journalctl -p warning
```

Afficher les événements SSH :

```bash
sudo journalctl -u ssh
```

Selon la configuration du système :

```bash
sudo tail -50 /var/log/auth.log
```

---

# Vérification des mises à jour

Actualiser la liste des packages :

```bash
sudo apt update
```

Afficher les packages pouvant être mis à jour :

```bash
apt list --upgradable
```

> Ne lancez pas nécessairement `apt upgrade` avant l'exercice : le niveau de mise à jour du serveur peut faire partie du TP.

---

# Réinitialisation du laboratoire

Si vous devez recommencer le TP depuis le début :

```bash
sudo ./prepare-lab.sh --reset
```

Cette commande remet les principaux paramètres pédagogiques dans leur état initial.

Elle permet notamment de :

* recréer la configuration du laboratoire ;
* remettre les services utilisés par le TP dans leur état attendu ;
* réinitialiser les règles du firewall ;
* désactiver Fail2ban ;
* restaurer les paramètres nécessaires aux exercices.

---

# Recommandation importante

Avant de commencer à modifier la configuration du serveur, créez si possible un **snapshot de votre VM**.

Exemple :

```text
Ubuntu-TP-Initial
```

Cela permettra de revenir rapidement à l'état initial en cas de mauvaise manipulation.

---

# Attention à SSH

Lorsque vous modifiez :

```text
/etc/ssh/sshd_config
```

ou un fichier situé dans :

```text
/etc/ssh/sshd_config.d/
```

vérifiez toujours la configuration avant de redémarrer SSH :

```bash
sudo sshd -t
```

Si aucune erreur n'est affichée, vous pouvez ensuite appliquer la configuration.

Par exemple :

```bash
sudo systemctl reload ssh
```

> Une mauvaise configuration SSH peut vous faire perdre l'accès distant au serveur.

---

# Règles du laboratoire

Pendant les TP :

1. analysez avant de modifier ;
2. notez l'état initial ;
3. justifiez chaque modification ;
4. vérifiez le résultat après modification ;
5. ne désactivez pas un service uniquement parce que vous ne le connaissez pas ;
6. vérifiez les dépendances ;
7. conservez une possibilité de retour arrière ;
8. documentez les actions réalisées.

La démarche attendue est :

```text
Observer
   ↓
Comprendre
   ↓
Identifier le risque
   ↓
Proposer une correction
   ↓
Appliquer
   ↓
Tester
   ↓
Documenter
```

---

# Objectif final

À la fin des deux TP, vous devez être capable de transformer progressivement un serveur :

```text
INSTALLATION STANDARD
        ↓
INVENTAIRE
        ↓
AUDIT DES COMPTES
        ↓
AUDIT DES SERVICES
        ↓
AUDIT DES PORTS
        ↓
DURCISSEMENT SSH
        ↓
PARE-FEU
        ↓
FAIL2BAN
        ↓
CORRECTIFS
        ↓
JOURNALISATION
        ↓
SERVEUR DURCI
```

L'objectif n'est pas de « tout bloquer ».

L'objectif est de :

> **Réduire la surface d'attaque tout en conservant les services nécessaires au fonctionnement du système.**

---

## Références

Les travaux pratiques sont construits autour des principes et recommandations issus notamment de :

* ANSSI — Guide d'hygiène informatique ;
* CIS Benchmarks ;
* NIST Cybersecurity Framework ;
* documentation Ubuntu ;
* documentation OpenSSH ;
* documentation nftables ;
* documentation Fail2ban.

---

## Avertissement

Ce projet contient volontairement des configurations qui ne correspondent pas toutes aux bonnes pratiques de sécurité.

Elles ont été créées **uniquement à des fins pédagogiques**.

**N'exécutez pas ce script sur :**

* une machine de production ;
* un serveur contenant des données sensibles ;
* une machine directement exposée à Internet ;
* une infrastructure professionnelle.
