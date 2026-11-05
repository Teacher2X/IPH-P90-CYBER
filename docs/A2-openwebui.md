# A2 — OpenWebUI et découverte du réseau

## Ce que tu vas comprendre

Ton ordinateur a une **adresse IP** : c'est son numéro sur le réseau, comme
une adresse postale. Un **serveur** est un ordinateur qui attend des demandes ;
un **client** est un ordinateur qui les envoie.

OpenWebUI est un **serveur web** installé sur ta machine. Ton navigateur est le
**client**. Les deux peuvent être le même ordinateur… ou deux ordinateurs
différents sur le même réseau.

## Les trois informations à connaître

| Information | Exemple | Ce que ça veut dire |
|---|---|---|
| **Adresse IP** | `192.168.1.42` | ton numéro sur le réseau |
| **Masque** | `255.255.255.0` | quels numéros sont "dans ta rue" |
| **Passerelle** | `192.168.1.1` | la porte de sortie vers Internet |

Avec un masque `255.255.255.0`, tous les appareils `192.168.1.x` sont dans le
même réseau local : ils peuvent se parler directement.

## Accès

- Depuis ton ordinateur : `http://localhost:3000`
- Depuis un autre PC autorisé : `http://<TON_IP>:3000`

`localhost` veut dire « moi-même ». L'adresse IP veut dire « l'ordinateur
qui porte ce numéro », même s'il est ailleurs dans la salle.

## Authentification

Obligatoire (`WEBUI_AUTH=true`). Chaque élève a **son propre compte** : ses
conversations restent séparées des autres. L'enseignant crée le premier compte
administrateur, puis les comptes utilisateurs.

## Découverte graphique — Angry IP Scanner

Angry IP Scanner envoie un petit signal à chaque adresse d'un réseau et affiche
qui répond. C'est un outil **pédagogique**, pas un outil d'attaque.

**Règle absolue** : ne scanner que le sous-réseau approuvé par l'enseignant
(par exemple `192.168.1.0/24` de la salle de classe). Scanner les réseaux de
l'établissement est interdit.

## Schéma à retenir

```
   [Ordinateur A]            [Ordinateur B]
   192.168.1.42               192.168.1.57
        |                          |
        +--------[ switch ]--------+
                     |
              réseau local 192.168.1.0/24
                     |
              [ passerelle 192.168.1.1 ] → Internet
```

- Le **port** (3000) indique quel service, sur une même machine.
  Une machine = une adresse ; un service = un port.

## Sécurité

- Ollama (port 11434) reste **invisible** depuis le réseau : seul OpenWebUI
  lui parle, à l'intérieur de Docker.
- L'accès réseau à OpenWebUI est limité par une **règle de pare-feu** sur le
  réseau pédagogique, pas seulement par le mot de passe.
- Docker n'est jamais exposé aux élèves.

## Commandes

```bash
p90 install A2-openwebui
p90 repair A2-openwebui
```

## À toi de jouer

1. Affiche ton IP : `ip -4 addr show`.
2. Ouvre OpenWebUI depuis ton voisin autorisé.
3. Lance Angry IP Scanner et trouve combien d'appareils répondent.
4. Explique pourquoi ton voisin voit OpenWebUI mais pas Ollama.
