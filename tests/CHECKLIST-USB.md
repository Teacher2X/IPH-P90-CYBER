# Checklist manuelle — validation sur clé USB réelle

> **Une validation statique ne suffit pas.** Ce document liste ce qui doit être
> vérifié sur une vraie clé Xubuntu persistante, sur du matériel réel.

Machine de test : ______________________
Date : ______________  Testeur : ______________
Clé USB : ______________ (taille : ____ Go)

---

## 0. Préparation

- [ ] Xubuntu LTS 64 bits installé sur la clé avec persistance active
- [ ] Démarrage depuis la clé OK
- [ ] Connexion réseau disponible (Ethernet ou Wi-Fi)
- [ ] PC sans GPU dédié (cas le plus défavorable)
- [ ] RAM notée : ______ Go

## 1. Bootstrap

- [ ] `curl … | bash` se termine sans erreur
- [ ] `/opt/p90-launcher/VERSION` existe et contient la bonne version
- [ ] `~/.p90-data/` créé
- [ ] Raccourci `~/Desktop/p90-launcher.desktop` présent et cliquable
- [ ] Après nouveau terminal : `p90 --version` répond
- [ ] **Rejouer le bootstrap** : aucune donnée effacée
- [ ] Bootstrap **sans réseau** : message d'erreur clair, pas de corruption

## 2. Interface graphique

- [ ] `p90` ouvre la fenêtre YAD sans terminal visible
- [ ] Les 5 modules A1–A5 sont listés avec nom + description
- [ ] Les états s'affichent (absent/installé/prêt/défaillant)
- [ ] Boutons Installer / Lancer / Vérifier / Réparer présents
- [ ] `p90 doctor` produit un rapport lisible
- [ ] `p90 doctor --file /tmp/r.txt` écrit bien le fichier
- [ ] Ouverture de la doc depuis la GUI

## 3. A1 — Ollama

- [ ] `p90 install A1-ollama` installe sans erreur
- [ ] `ollama --version` répond
- [ ] Le service répond sur `localhost:11434`
- [ ] Le modèle proposé correspond à la RAM
- [ ] Téléchargement confirmé **par l'utilisateur**, pas automatique
- [ ] `ollama run <modèle>` génère une **vraie** réponse
- [ ] **Redémarrage** → modèle toujours présent, service OK
- [ ] `curl http://<IP_LAN>:11434` **échoue** (port non exposé) ✅ sécurité
- [ ] Terminal XFCE s'ouvre depuis le bouton Lancer

## 4. A2 — OpenWebUI

- [ ] Docker installé et `docker compose version` OK
- [ ] `p90 install A2-openwebui` démarre les conteneurs
- [ ] `http://localhost:3000` affiche la page de connexion
- [ ] **Inscription impossible sans créer de compte** (auth active)
- [ ] Création compte admin OK, puis second compte utilisateur
- [ ] Les conversations du compte A ne sont **pas** visibles par le compte B
- [ ] Depuis un autre PC autorisé : `http://<IP>:3000` affiche le login
- [ ] Depuis un PC **non autorisé** (règle pare-feu) : accès **bloqué**
- [ ] `curl http://<IP>:11434` depuis un autre PC : **échoue**
- [ ] **Redémarrage** → conversations toujours là
- [ ] Angry IP Scanner démarre graphiquement
- [ ] Scan limité au sous-réseau approuvé

## 5. A3 — Hermes

- [ ] `p90 install A3-hermes` se termine
- [ ] `hermes --version` répond
- [ ] Hermes utilise bien Ollama (aucun appel cloud)
- [ ] Tâche 1 : réponse textuelle OK
- [ ] Tâche 2 : lecture + résumé d'un fichier, résumé conforme
- [ ] Tâche 3 : création d'un fichier dans l'espace de travail — vérifié sur disque
- [ ] L'agent **ne peut pas** écrire hors de son espace de travail
- [ ] L'agent **ne peut pas** lire `~/.ssh`
- [ ] Espace de travail : `~/.p90-data/hermes-workspace`

## 6. A4 — WhatsApp (facultatif)

- [ ] Module **désactivé** au départ (non installé)
- [ ] Mot de passe WAHA défini avant démarrage
- [ ] `http://localhost:3001` inaccessible depuis un autre PC
- [ ] QR code affiché, appairage OK avec le compte de démonstration
- [ ] Réception d'un message de test
- [ ] Réponse de l'IA renvoyée sur WhatsApp
- [ ] **Redémarrage** → session conservée, pas de nouveau QR
- [ ] Arrêt du pont depuis P90
- [ ] Journaux : aucun contenu de message en clair

## 7. A5 — Profils / mémoire / RAG

- [ ] Trois profils créés et listés
- [ ] Question identique aux 3 profils → personnalités distinctes
- [ ] Fait mémorisé → présent dans `MEMORY.md`
- [ ] **Redémarrage** → fait toujours mémorisé
- [ ] Suppression du fait → l'agent l'oublie
- [ ] Recherche dans les anciennes sessions OK
- [ ] Question sur un document → réponse avec **source citée**
- [ ] Aucune fuite de mémoire entre profils

## 8. Persistance globale

Après un redémarrage complet de la clé :

- [ ] Modèles Ollama présents
- [ ] Conversations OpenWebUI présentes
- [ ] Profils + sessions Hermes présents
- [ ] Fichiers pédagogiques présents
- [ ] Configuration des modules conservée (`.state`)
- [ ] Index RAG présent
- [ ] Session WhatsApp (si A4) conservée

## 9. Maintenance

- [ ] `p90 repair A1` ne supprime aucune donnée
- [ ] `p90 status` reflète l'état réel
- [ ] `p90 update` (hors-ligne) : message clair, pas de crash
- [ ] Installation interrompue (Ctrl-C) : reprise possible
- [ ] Coupure réseau pendant installation : message pédagogique

## 10. Sécurité finale

- [ ] Aucun service ne tourne en root de façon permanente
- [ ] Aucun secret dans le dépôt Git (`git grep` sur les motifs habituels)
- [ ] Aucun port administratif exposé au LAN
- [ ] Aucun redémarrage imposé sans confirmation
- [ ] Aucun disque interne touché, aucun repartitionnement

---

## Verdict de la campagne

- [ ] PASS — tout vérifié
- [ ] PARTIAL — vérifié avec réserves (préciser) :

      ______________________________________________

- [ ] FAIL — bloquant (préciser) :

      ______________________________________________

Signature : ______________
