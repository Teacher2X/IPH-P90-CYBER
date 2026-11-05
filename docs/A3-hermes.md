# A3 — Hermes Agent : du chatbot à l'agent

## Ce que tu vas comprendre

Un **chatbot** répond du texte. Un **agent** peut en plus **utiliser des
outils** : lire un fichier, créer un document, lancer une commande.

La différence n'est pas la qualité des réponses : c'est la capacité d'**agir**
sur ta machine.

| | Chatbot | Agent |
|---|---|---|
| Écrit du texte | ✅ | ✅ |
| Lit un fichier | ❌ | ✅ |
| Crée un document | ❌ | ✅ |
| Peut se tromper en agissant | — | ⚠️ oui, c'est le risque |

## Une action = un outil

Hermes ne "sait" pas lire un fichier : il **demande** à un outil de le faire.
Le modèle décide quel outil appeler, avec quels paramètres, puis lit le
résultat et continue.

```
Question → le modèle réfléchit → appelle un outil → lit le résultat
        → continue → répond
```

## Les trois exercices

1. **Répondre** : *« Qu'est-ce qu'une adresse IPv4 ? »*
   → aucune action, juste du texte.

2. **Lire et résumer** : *« Résume le fichier docs/A1-ollama.md »*
   → l'agent appelle un outil de lecture, puis résume.
   Vérifie toi-même : le résumé correspond-il au fichier ?

3. **Créer** : *« Crée un fichier note.txt dans l'espace de travail avec trois
   conseils de sécurité réseau »*
   → l'agent écrit un fichier. Va voir : il existe vraiment.

## Sécurité — ce qui est interdit à l'agent

- Modifier le système.
- Lire les secrets (`~/.ssh`, `.env`, mots de passe).
- Lancer des commandes destructrices (`rm -rf`, formatage).
- Accéder aux fichiers des autres élèves.
- Faire des actions réseau non autorisées.

L'espace de travail dédié est : `~/.p90-data/hermes-workspace`.
L'agent travaille **là**, pas ailleurs.

## Modèle local

Hermes utilise **Ollama en local**. Aucun compte cloud, aucun service payant.
C'est plus lent qu'un modèle en ligne, mais rien ne sort de la machine.

## Commandes

```bash
p90 install A3-hermes
p90 repair A3-hermes
```

## À toi de jouer

1. Pose la question 1 et observe : aucun outil n'est appelé.
2. Demande le résumé du fichier : quel outil a été utilisé ?
3. Demande la création du fichier : vérifie avec `ls ~/.p90-data/hermes-workspace`.
4. Trouve une demande qui **échouerait** parce que l'agent n'a pas le droit.

## Point de vigilance

Un agent qui agit peut aussi se tromper. Ne lui fais jamais confiance pour une
action importante sans vérifier le résultat toi-même.
