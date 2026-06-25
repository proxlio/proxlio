# Proxlio — Projet

> Idée émergée le 2026-06-25, conversation Claude Code / Cédric  
> **Nom retenu : Proxlio** (proxy + local + -io) — vérifié libre, aucun conflit de marque  
> **Domaines** : `proxlio.com` (principal) · `proxl.io` (lien court)

---

## Problème résolu

Il n'existe aucun produit grand public qui combine en une seule installation :
- **Reverse proxy L7** (routage par nom de domaine, SSL automatique)
- **DNS intelligent** (split DNS, rewrites locaux, ad blocking)
- **Tunnel externe** (accès depuis internet sans ouvrir de port)

Les routeurs (UniFi, Asus, GL.iNet) s'arrêtent à la couche 3/4 (IP/port).
Les solutions actuelles (NPM + AdGuard + Cloudflare Tunnel) nécessitent 3 outils séparés, des connaissances Docker, et plusieurs heures de configuration.

---

## Solution

**Kit logiciel "1-click"** qui installe et configure automatiquement l'infrastructure complète, avec un assistant web guidé accessible à tout technophile (pas forcément sysadmin).

### Briques techniques (toutes open source)
- Reverse proxy : **NPM** ou **Caddy** (SSL Let's Encrypt automatique)
- DNS : **AdGuard Home** (rewrites locaux + ad blocking)
- Tunnel externe : **Cloudflare Tunnel** (pas d'ouverture de port)
- Orchestration : **Docker Compose**
- UI wizard : à construire (React/Vue + backend Go ou Python)

### Différenciation clé
- **Auto-découverte des services LAN** : scan des ports + mDNS → propose automatiquement d'exposer chaque service détecté
- **3 clics pour ajouter un service** : nom de domaine → sous-domaine créé, DNS rewrite créé, certificat SSL généré, proxy configuré
- **Dashboard unifié** : statut de tous les services en temps réel
- **Assistant de débogage** : messages d'erreur clairs pour les cas limites réseau (CGNAT, IPv6, port 80 bloqué)

---

## Modèle économique

**Open Core + SaaS**

| Tier | Prix | Contenu |
|------|------|---------|
| Free | 0€ | Logiciel local open source, 3 services, installation guidée |
| Home | 4€/mois | Services illimités, backup config cloud, alertes email |
| Pro | 12€/mois | Multi-site, support prioritaire, monitoring avancé |

**Autres leviers :**
- Hardware bundle : mini-PC préconfiguré 150-200€ (1 an Pro inclus)
- Onboarding payant : session 1h à 99€
- Affiliation : Cloudflare, registrars domaines

---

## Cible

**Persona principal** : technophile avec 3-10 services self-hostés (Home Assistant, NAS, Ollama, n8n...), pas sysadmin professionnel. Sait ce qu'est Docker, a un RPI ou mini-PC, mais perd des heures sur la config réseau.

**Communautés** : r/selfhosted (2M membres), r/homelab, forums UniFi, YouTube homelab

---

## Avantage concurrentiel

**L'IA comme levier opérationnel** — modèle inaccessible aux concurrents solo classiques :

- **Nova (Hermes / EVO-X2)** tourne en arrière-plan et gère la communauté en autonomie :
  - Triage automatique des issues GitHub (classification, labels, demande d'infos)
  - Réponses aux questions fréquentes + détection des duplicates
  - Génération de documentation depuis les issues résolues
  - Surveillance Reddit/Discord → alertes Telegram si mention du projet
  - Résumé quotidien Telegram : "3 issues nécessitent ta décision"
- **Claude Code** pour l'exécution technique (code, refactoring, tests)
- **Cédric** = product owner + vision + décisions roadmap

→ Opère à la vitesse d'une petite équipe, coûts fixes quasi nuls.

---

## Roadmap envisagée

### Phase 1 — MVP (2-4 semaines avec Claude/Nova)
- [ ] Script d'installation Docker Compose (NPM + AdGuard + Cloudflare Tunnel)
- [ ] Wizard web de configuration initiale (10 étapes)
- [ ] Auto-découverte des services LAN
- [ ] Ajout d'un service en 3 clics (sous-domaine + DNS rewrite + SSL)
- [ ] Testé sur l'infra Cédric (Freebox + RPI5 + Cloudflare)

### Phase 2 — Beta ouverte
- [ ] Repo GitHub public + README
- [ ] Post r/selfhosted pour recruter bêta testeurs
- [ ] Automatisation triage issues (Nova)
- [ ] Support multi-ISP basé sur retours communauté

### Phase 3 — Monétisation
- [ ] Services cloud (backup config, alertes)
- [ ] Landing page + système de paiement
- [ ] Hardware bundle (partenariat ou dropshipping)

---

## Concurrents à surveiller

| Produit | Force | Limite |
|---------|-------|--------|
| Zoraxy | Reverse proxy Go léger, SSL auto | Pas de DNS intégré, trop technique |
| GL.iNet Flint 2 | AdGuard intégré, hardware clé en main | Pas de reverse proxy |
| Tailscale | VPN mesh simple | Pas de reverse proxy, pas de split DNS LAN |
| Cloudflare Zero Trust | Tunnel gratuit robuste | Pas de DNS LAN, pas de self-hosted |
| NPM + AdGuard (séparés) | Battle-tested, communauté énorme | Pas d'UX unifiée, config manuelle |

---

## Risques

- **Cloudflare sort un produit similaire** → moat = UX + communauté + open source
- **Support coûteux** → automatisation Nova + doc générée depuis issues
- **Marché de niche** → plafond MRR réaliste 2-8k€ à 18 mois, pas une licorne
- **Distribution** → canaux : r/selfhosted, YouTube homelab, forums UniFi/HA

---

## Prochaine étape

- Réserver `proxlio.com` + `proxl.io` (Cloudflare Registrar recommandé)
- Créer le repo GitHub public `proxlio`

> Ce projet est à démarrer après la migration EVO-X2 + Nova opérationnel.
