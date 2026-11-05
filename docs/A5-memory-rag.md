# A5 — Profils, mémoire et RAG

## Ce que tu vas comprendre

Quatre choses que l'on confond souvent :

| Notion | Ce que c'est | Où c'est stocké |
|---|---|---|
| **Le LLM** | le moteur qui génère du texte | le modèle Ollama |
| **Le profil** | des instructions + une mémoire + des sessions | `~/.hermes/profiles/<nom>/` |
| **La mémoire** | des faits retenus entre deux conversations | `MEMORY.md`, `SOUL.md`, `USER.md` |
| **Le RAG** | des documents retrouvés à la demande | tes fichiers + un index |

## Étape 1 — Les profils

Trois profils sont créés :

- `p90-assistant` — aide générale.
- `p90-reseau` — explications réseau et cybersécurité.
- `p90-documentation` — lecture et analyse de documents.

Chaque profil a **ses propres** instructions, sessions et mémoire. Ce que tu
dis à l'un ne doit pas fuiter chez l'autre.

Expérience : pose la même question aux trois profils. Les réponses doivent
différer par la **forme**, pas seulement par le fait.

## Étape 2 — La mémoire

Une conversation est **temporaire** : ferme-la, tout disparaît.
La mémoire est **durable** : elle reste après redémarrage.

```bash
# Voir la mémoire d'un profil
cat ~/.hermes/profiles/p90-assistant/MEMORY.md
```

Tu peux **consulter**, **corriger** et **supprimer** ces fichiers : ce sont des
fichiers texte, rien de caché.

**Règle absolue** : jamais de mot de passe, jamais de donnée personnelle
sensible dans la mémoire d'un agent.

Expérience :
1. Dis à l'agent un fait (« J'ai un frère qui s'appelle Léo »).
2. Ferme la conversation.
3. Rouvre-la et pose une question sur Léo : l'agent s'en souvient-il ?
4. Regarde `MEMORY.md` : le fait y est-il écrit ?

## Étape 3 — Le RAG

Le RAG (*Retrieval-Augmented Generation*) = **chercher dans tes documents**
avant de répondre, puis **citer la source**.

```
Question → recherche dans les documents → extraits trouvés
        → donnés au modèle → réponse + référence du document
```

Les documents vont dans `~/.p90-data/documents-pedagogiques`.

On utilise d'abord les fonctions documentaires **déjà présentes** dans
OpenWebUI et Hermes. Aucun serveur vectoriel supplémentaire n'est déployé :
ça n'apporterait rien à ce niveau.

Expérience :
1. Déposer un document (ex. une fiche de cours) dans le dossier.
2. Poser une question dont la réponse est dans le document.
3. Vérifier que la réponse **cite le document**.

## Commandes

```bash
p90 install A5-memory-rag
p90 repair A5-memory-rag
```

## À toi de jouer

1. Pose la même question aux trois profils. Compare.
2. Fais mémoriser un fait, redémarre, vérifie qu'il est toujours là.
3. Supprime ce fait de `MEMORY.md` : l'agent l'a-t-il oublié ?
4. Pose une question sur un document déposé : la source est-elle citée ?

## Point de vigilance

Une mémoire fausse est pire qu'une absence de mémoire. Relis régulièrement ce
que l'agent a retenu, et corrige.
