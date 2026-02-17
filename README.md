# Zeroclaw auf Synology NAS via Portainer

## Inhaltsverzeichnis

1. [Voraussetzungen](#1-voraussetzungen)
2. [Erstinstallation](#2-erstinstallation)
3. [Konfiguration](#3-konfiguration)
4. [Messaging-Kanäle einrichten](#4-messaging-kanäle-einrichten)
5. [Updates](#5-updates)
6. [Backup & Restore](#6-backup--restore)
7. [Reverse Proxy (HTTPS)](#7-reverse-proxy-https)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Voraussetzungen

### Hardware

| Anforderung | Minimum | Empfohlen |
|---|---|---|
| Synology Modell | Jedes x86-64 Modell | DS220+, DS423, DS920+ oder neuer |
| RAM | 2 GB frei | 4 GB frei |
| Speicher | 2 GB | 4 GB (für Docker-Images und Build-Cache) |
| CPU | x86-64 | Intel Celeron J4125 oder besser |

### Software

- **DSM 7.0+** (empfohlen: DSM 7.2+)
- **Container Manager** — installierbar über das DSM Paketzentrum
- **Portainer** — läuft bereits auf deiner NAS

### API-Keys

Du brauchst mindestens **einen** LLM-API-Key:

| Provider | Registrierung | Kosten |
|---|---|---|
| Anthropic (Claude) | https://console.anthropic.com | Pay-per-use |
| OpenAI | https://platform.openai.com | Pay-per-use |
| OpenRouter | https://openrouter.ai | Pay-per-use, viele Modelle |
| Groq | https://console.groq.com | Gratis-Tier verfügbar |

---

## 2. Erstinstallation

### Schritt 1: Image bauen via Portainer

1. Öffne **Portainer** (`https://NAS-IP:9443`)
2. Gehe zu **Images → Build a new image**
3. **Name:** `zeroclaw:latest`
4. Wähle **URL** und gib ein:
   ```
   https://raw.githubusercontent.com/dmayk/zeroclaw/main/Dockerfile
   ```
   **Oder** wähle **Web editor** und kopiere den Inhalt des Dockerfiles hinein:
   https://github.com/dmayk/zeroclaw/blob/main/Dockerfile
5. Klicke **Build the image**
6. Warte 10-30 Minuten (Rust-Compilation) — Fortschritt wird live angezeigt

> **Hinweis:** Portainer braucht einen Build-Kontext. Da unser Dockerfile
> das Repository selbst klont, kannst du den Build-Kontext leer lassen
> oder auf ein leeres Verzeichnis zeigen lassen.

### Schritt 2: Stack in Portainer erstellen

1. Öffne **Portainer** (`https://NAS-IP:9443`)
2. **Stacks → Add Stack**
3. **Name:** `zeroclaw`
4. **Build method:** **Web editor**
5. Kopiere den Inhalt der `docker-compose.yml` aus dem Repo hinein:
   https://github.com/dmayk/zeroclaw/blob/main/docker-compose.yml

### Schritt 3: Environment-Variablen setzen

Scrolle nach unten zu **Environment variables** → **Advanced mode**.

Pflicht (eine Zeile pro Variable):

```
ZEROCLAW_API_KEY=sk-ant-DEIN_ANTHROPIC_KEY_HIER
```

Empfohlen:

```
ZEROCLAW_PROVIDER=anthropic
ZEROCLAW_MODEL=claude-sonnet-4-5-20250929
ZEROCLAW_MEMORY_BACKEND=sqlite
ZEROCLAW_AUTONOMY=supervised
```

> Alle Einstellungen die früher in der config.toml standen werden jetzt
> als Environment-Variablen gesetzt. Siehe [Konfiguration](#3-konfiguration)
> für die vollständige Liste.

### Schritt 4: Deploy

1. Klicke **Deploy the stack**
2. Container startet in wenigen Sekunden

### Schritt 5: Prüfen

1. **Containers → zeroclaw** → sollte **Running** (grün) sein
2. Klicke auf den Container → **Logs** → prüfe auf Fehler
3. **Console → `/bin/bash`** → `zeroclaw doctor`

---

## 3. Konfiguration

**Alles wird über Portainer Environment-Variablen gesteuert.**

Ändern: **Stacks → zeroclaw → Editor → Environment variables → Update the stack**

### Vollständige Variablen-Referenz

#### LLM Provider

| Variable | Default | Beschreibung |
|---|---|---|
| `ZEROCLAW_API_KEY` | — | **Pflicht.** API-Key deines LLM-Providers |
| `ZEROCLAW_PROVIDER` | `anthropic` | Provider: `anthropic`, `openai`, `openrouter`, `groq`, `ollama`, etc. |
| `ZEROCLAW_MODEL` | `claude-sonnet-4-5-20250929` | Modell-ID |

#### Memory

| Variable | Default | Beschreibung |
|---|---|---|
| `ZEROCLAW_MEMORY_BACKEND` | `sqlite` | `sqlite`, `markdown`, oder `none` |
| `ZEROCLAW_EMBEDDING_PROVIDER` | `openai` | Provider für Vektor-Embeddings |
| `ZEROCLAW_EMBEDDING_MODEL` | `text-embedding-3-small` | Embedding-Modell |
| `ZEROCLAW_EMBEDDING_API_KEY` | — | API-Key für Embeddings (oft = OpenAI Key) |

#### Gateway & Security

| Variable | Default | Beschreibung |
|---|---|---|
| `ZEROCLAW_GATEWAY_HOST` | `0.0.0.0` | Bind-Adresse |
| `ZEROCLAW_GATEWAY_PORT` | `3000` | HTTP-Port |
| `ZEROCLAW_AUTONOMY` | `supervised` | `readonly`, `supervised`, oder `full` |
| `ZEROCLAW_IDENTITY_NAME` | `Zeroclaw` | Name deines Agenten |

#### Messaging-Kanäle

| Variable | Beschreibung |
|---|---|
| `ZEROCLAW_TELEGRAM_TOKEN` | Telegram Bot-Token |
| `ZEROCLAW_DISCORD_TOKEN` | Discord Bot-Token |
| `ZEROCLAW_SLACK_BOT_TOKEN` | Slack Bot-Token |
| `ZEROCLAW_SLACK_APP_TOKEN` | Slack App-Token |
| `ZEROCLAW_SLACK_SIGNING_SECRET` | Slack Signing Secret |
| `ZEROCLAW_WHATSAPP_TOKEN` | WhatsApp Business API Token |
| `ZEROCLAW_WHATSAPP_VERIFY_TOKEN` | WhatsApp Verify Token |
| `ZEROCLAW_WHATSAPP_PHONE_NUMBER_ID` | WhatsApp Phone Number ID |
| `ZEROCLAW_MATRIX_ACCESS_TOKEN` | Matrix Access Token |
| `ZEROCLAW_MATRIX_USER_ID` | Matrix User ID (z.B. `@bot:matrix.org`) |
| `ZEROCLAW_EMAIL_USER` | Email-Adresse |
| `ZEROCLAW_EMAIL_PASSWORD` | Email App-Passwort |
| `ZEROCLAW_EMAIL_IMAP_HOST` | IMAP-Server (z.B. `imap.gmail.com`) |
| `ZEROCLAW_EMAIL_IMAP_PORT` | IMAP-Port (Default: `993`) |
| `ZEROCLAW_EMAIL_SMTP_HOST` | SMTP-Server (z.B. `smtp.gmail.com`) |
| `ZEROCLAW_EMAIL_SMTP_PORT` | SMTP-Port (Default: `587`) |

#### Tunnel (Remote-Zugriff)

| Variable | Beschreibung |
|---|---|
| `ZEROCLAW_TUNNEL_KIND` | `cloudflare`, `tailscale`, `ngrok`, oder leer |
| `ZEROCLAW_TUNNEL_TOKEN` | Token des Tunnel-Providers |

### Persistente Daten

Alle Daten liegen auf dem NAS unter `/volume1/docker/zeroclaw/data/`:

| Datei | Inhalt |
|---|---|
| `memory.db` | SQLite — Konversationen & Vektor-Embeddings |
| `.secret_key` | Verschlüsselungsschlüssel (ChaCha20-Poly1305) |
| `workspace/` | Identitäts- und Arbeitsdateien |

Sichtbar in **File Station** → `docker/zeroclaw/data/`.

---

## 4. Messaging-Kanäle einrichten

### Telegram (empfohlen für den Einstieg)

1. Öffne Telegram → suche `@BotFather` → sende `/newbot` → kopiere Token
2. In Portainer Environment hinzufügen:
   ```
   ZEROCLAW_TELEGRAM_TOKEN=123456789:ABCdefGHIjklMNO
   ```
3. **Update the stack**
4. Sende deinem Bot eine Nachricht — fertig

> Ohne HTTPS nutzt Zeroclaw automatisch Long-Polling. Kein Reverse Proxy nötig.

### Discord

1. https://discord.com/developers/applications → Bot erstellen
2. `MESSAGE_CONTENT` Intent aktivieren
3. Bot zu deinem Server einladen (OAuth2 → bot Scope)
4. In Portainer: `ZEROCLAW_DISCORD_TOKEN=MTIz...`
5. Update the stack

### Slack

1. https://api.slack.com/apps → App erstellen
2. Bot Token + App Token generieren
3. In Portainer alle drei Variablen setzen
4. Update the stack

---

## 5. Updates

### Standard-Update via Portainer

1. **Images → Build a new image**
2. Name: `zeroclaw:latest`
3. Dockerfile wie bei der Erstinstallation einfügen (oder URL)
4. **Build the image** (10-30 Minuten)
5. **Containers → zeroclaw → Recreate** → Haken bei **Pull latest image** deaktivieren → **Recreate**

Das Dockerfile klont automatisch den neuesten `main` Branch bei jedem Build.

### Update auf eine bestimmte Version

Ändere im Dockerfile vor dem Build die `ARG` Zeile:

```dockerfile
ARG ZEROCLAW_VERSION=v0.6.0
```

Oder nutze per SSH:

```bash
cd /volume1/docker/zeroclaw
sudo docker build -t zeroclaw:latest --build-arg ZEROCLAW_VERSION=v0.6.0 --no-cache .
```

Dann in Portainer: **Containers → zeroclaw → Recreate**.

---

## 6. Backup & Restore

### Was sichern?

| Was | Wo | Priorität |
|---|---|---|
| Environment-Variablen | Portainer Stack-Einstellungen | Kritisch — notiere deine Keys separat! |
| Persistente Daten | `/volume1/docker/zeroclaw/data/` | Hoch |

### Backup

Per **File Station**: `docker/zeroclaw/data/` Ordner kopieren oder herunterladen.

### Restore

Per **File Station**: `data/` Ordner zurückkopieren nach `docker/zeroclaw/data/`.
Dann in Portainer den Container neu starten.

### Hyper Backup

Füge diesen Pfad zu deinem Hyper Backup Task hinzu:

- `/volume1/docker/zeroclaw/data/`

---

## 7. Reverse Proxy (HTTPS)

Nur nötig für Webhook-basierte Kanäle (Slack, WhatsApp). Telegram und Discord
funktionieren auch ohne HTTPS im Polling-Modus.

### Option A: Synology Reverse Proxy

1. **DSM → Systemsteuerung → Anmeldeportal → Erweitert → Reverse Proxy**
2. Erstellen:
   - Quelle: HTTPS, `zeroclaw.deine-domain.de`, Port 443
   - Ziel: HTTP, `localhost`, Port 3000
3. SSL-Zertifikat via Let's Encrypt einrichten

### Option B: Cloudflare Tunnel

In Portainer Environment:

```
ZEROCLAW_TUNNEL_KIND=cloudflare
ZEROCLAW_TUNNEL_TOKEN=dein-cloudflare-tunnel-token
```

---

## 8. Troubleshooting

### Build: Out of Memory

Stoppe andere Container in Portainer während des Builds
(**Containers → Select all → Stop**).

### Container startet nicht

1. **Portainer → Containers → zeroclaw → Logs**
2. Häufigste Ursache: Fehlender `ZEROCLAW_API_KEY`

### Speicher aufräumen

In Portainer: **Images → Unused images** aufräumen und **Volumes → Unused volumes** aufräumen.

---

## Quick Reference

| Aktion | Portainer-Pfad |
|---|---|
| Image bauen | Images → Build a new image |
| Stack deployen | Stacks → zeroclaw → Deploy |
| Config ändern | Stacks → zeroclaw → Editor → Environment → Update |
| Logs | Containers → zeroclaw → Logs |
| Shell | Containers → zeroclaw → Console → `/bin/bash` |
| Neustart | Containers → zeroclaw → Restart |
| Update anwenden | Containers → zeroclaw → Recreate |
