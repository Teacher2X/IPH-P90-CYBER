# A4 — Pont WhatsApp (module facultatif)

> ⚠️ **Module désactivé par défaut.** Activité de démonstration seulement,
> avec un compte dédié, sous la responsabilité de l'enseignant.

## Ce que tu vas comprendre

Comment un message envoyé depuis un téléphone peut arriver à une IA qui tourne
sur un ordinateur — et revenir.

C'est une **chaîne de services** :

```
WhatsApp  →  WAHA  →  adaptateur  →  Hermes / Ollama  →  réponse  →  WhatsApp
```

Chaque maillon fait une seule chose. Si un maillon casse, toute la chaîne
s'arrête : c'est pour ça qu'on les sépare.

## Pourquoi WAHA et pas une autre solution ?

WAHA (*WhatsApp HTTP API*) transforme WhatsApp en **API HTTP** : on lui envoie
une requête, il envoie un message. C'est un projet libre, auto-hébergé, qui
garde la session (le QR code scanné) sur la machine.

## Risques — à lire avant de commencer

- **WAHA n'est pas officiel.** WhatsApp peut **bloquer** le numéro utilisé.
- Utilise un **compte de démonstration dédié**, jamais un compte personnel,
  jamais le compte d'un élève.
- **Aucun envoi en masse.** Un seul contact de test, autorisé par l'enseignant.
- **Ne jamais** donner accès au carnet de contacts.
- Vérifie les conditions d'utilisation de WhatsApp avant l'activité.

## Ce qui est protégé

- Le dashboard n'écoute que sur `127.0.0.1` : inaccessible depuis le réseau.
- Mot de passe obligatoire (`P90_WAHA_PASSWORD`).
- Les messages ne sont pas écrits en clair dans les journaux.
- Arrêt immédiat possible depuis le lanceur P90.

## Mise en route

1. Définir un mot de passe : `export P90_WAHA_PASSWORD='...'`
2. `p90 install A4-whatsapp`
3. Ouvrir `http://localhost:3001` et scanner le QR code avec le téléphone de
   démonstration.
4. Envoyer un message depuis le contact de test autorisé.
5. Vérifier que la réponse revient.

La session persiste sur la clé USB : après redémarrage, pas besoin de rescanner.

## Arrêt

```bash
p90 repair A4-whatsapp   # redémarrer
# ou arrêt immédiat depuis la GUI (bouton d'arrêt du module)
```

## Ce qu'on ne fait pas dans cette activité

- Envoyer à plusieurs contacts.
- Lire les conversations des élèves.
- Automatiser sans surveillance.
- Utiliser n8n : un adaptateur léger suffit pour la démonstration.
