# Zeroclaw auf Synology NAS via Portainer — Setup & Betriebsanleitung

## Inhaltsverzeichnis

1. [Voraussetzungen](#1-voraussetzungen)
2. [Erstinstallation](#2-erstinstallation)
3. [Konfiguration](#3-konfiguration)
4. [Betrieb & Überwachung](#4-betrieb--überwachung)
5. [Messaging-Kanäle einrichten](#5-messaging-kanäle-einrichten)
6. [Updates](#6-updates)
7. [Backup & Restore](#7-backup--restore)
8. [Reverse Proxy (HTTPS)](#8-reverse-proxy-https)
9. [Troubleshooting](#9-troubleshooting)
10. [Sicherheitshinweise](#10-sicherheitshinweise)

---

## 1. Voraussetzungen

### Hardware

| Anforderung | Minimum | Empfohlen |
|---|---|---|
| Synology Modell | Jedes x86-64 Modell | DS220+, DS423, DS920+ oder neuer |
| RAM | 2 GB frei | 4 GB frei |
| Speicher | 500 MB | 2 GB (für Docker-Images und Build-Cache) |
| CPU | x86-64 | Intel Celeron J4125 oder besser |

> **Hinweis:** ARM-basierte Synology-Modelle (z.B. DS120j) funktionieren theoretisch,
> aber der Rust-Build dauert dort sehr lange (~1h+). Bei ARM-Geräten empfiehlt sich
> Cross-Compilation auf einem anderen Rechner.

### Software

- **DSM 7.0+** (empfohlen: DSM 7.2+)
- **Container Manager** (ehemals Docker) — installierbar über das DSM Paketzentrum
- **Portainer** — läuft bereits auf deiner NAS
- **SSH-Zugang** aktiviert (Systemsteuerung → Terminal & SNMP → SSH aktivieren)
- **Git** — auf DSM 7 vorinstalliert, prüfe mit `git --version` per SSH

### Accounts & API-Keys

Du brauchst mindestens **einen** LLM-API-Key:

| Provider | Registrierung | Kosten |
|---|---|---|
| Anthropic (Claude) | https://console.anthropic.com | Pay-per-use (~$3/M input tokens für Sonnet) |
| OpenAI | https://platform.openai.com | Pay-per-use |
| OpenRouter | https://openrouter.ai | Pay-per-use, viele Modelle |
| Groq | https://console.groq.com | Gratis-Tier verfügbar |

Für Memory-Embeddings brauchst du zusätzlich einen OpenAI-Key
(oder du nutzt `memory.backend = "markdown"` ohne Embeddings).

---

## 2. Erstinstallation

### Verzeichnisstruktur

Das Ziel ist eine saubere Trennung: das originale Repo bleibt unverändert,
deine Overrides (Dockerfile, Compose, Config) liegen daneben.

```
/volume1/docker/zeroclaw/           ← dein Projektverzeichnis
├── docker-compose.yml              ← deine Compose-Datei
├── Dockerfile                      ← dein Dockerfile (baut aus dem Repo-Source)
├── config/
│   ├── config.toml                 ← deine aktive Konfiguration
│   └── config.toml.example         ← Referenz-Template
├── data/                           ← persistente Daten (SQLite, Secret Key, Workspace)
│   ├── memory.db                   ← Konversationshistorie & Vektor-Embeddings
│   ├── .secret_key                 ← Verschlüsselungsschlüssel
│   └── workspace/                  ← Identitäts- und Arbeitsdateien
└── repo/                           ← geklontes GitHub-Repo (git pull für Updates)
    ├── Cargo.toml
    ├── src/
    └── ...
```

> **Wichtig:** Alle persistenten Daten liegen in `data/` direkt auf dem NAS-Dateisystem
> (kein Docker-Volume). Dadurch sind sie sichtbar in File Station, einfach sicherbar
> mit Hyper Backup, und überleben ein `docker volume prune` oder Stack-Löschung.

### Schritt 1: Per SSH auf die NAS verbinden

```bash
ssh dein-user@NAS-IP
```

### Schritt 2: Projektverzeichnis erstellen und Repo klonen

```bash
sudo mkdir -p /volume1/docker/zeroclaw/{config,data}
cd /volume1/docker/zeroclaw

# Zeroclaw-Repo klonen
sudo git clone https://github.com/zeroclaw-labs/zeroclaw.git repo
```

Um auf einen bestimmten Release-Tag zu pinnen (empfohlen für Stabilität):

```bash
cd /volume1/docker/zeroclaw/repo
sudo git checkout v0.5.0    # oder den aktuellsten Release-Tag
cd ..
```

### Schritt 3: Override-Dateien auf die NAS bringen

Kopiere `Dockerfile`, `docker-compose.yml` und `config/config.toml.example`
von deinem lokalen Rechner auf die NAS:

```bash
# Von deinem Mac aus:
scp Dockerfile docker-compose.yml \
    dein-user@NAS-IP:/volume1/docker/zeroclaw/

scp config/config.toml.example \
    dein-user@NAS-IP:/volume1/docker/zeroclaw/config/
```

### Schritt 4: config.toml erstellen

```bash
# Per SSH auf der NAS:
cd /volume1/docker/zeroclaw
sudo cp config/config.toml.example config/config.toml
```

Bearbeite die config.toml — die wichtigsten Einstellungen:

```bash
sudo vi config/config.toml
```

```toml
[provider]
kind = "anthropic"
model = "claude-sonnet-4-5-20250929"

[memory]
backend = "sqlite"

[gateway]
host = "0.0.0.0"
port = 3000

[security]
autonomy = "supervised"
```

> API-Keys kommen NICHT in die config.toml — die werden in Portainer als
> Environment-Variablen gesetzt.

### Schritt 5: Image bauen

```bash
cd /volume1/docker/zeroclaw

# Image bauen (dauert beim ersten Mal 10-30 Minuten)
sudo docker build -t zeroclaw:latest -f Dockerfile repo/
```

> **Erklärung:** `-f Dockerfile` nutzt dein eigenes Dockerfile.
> `repo/` ist der Build-Kontext — der geklonte Quellcode wird per `COPY . .`
> ins Build-Image kopiert.

### Schritt 6: Stack in Portainer erstellen

1. Öffne **Portainer** im Browser (`https://NAS-IP:9443`)
2. Wähle deine Synology-Umgebung (Local)
3. Gehe zu **Stacks → Add Stack**
4. **Name:** `zeroclaw`
5. **Build method:** Wähle **Web editor**
6. Kopiere den Inhalt der `docker-compose.yml` hinein
7. **Wichtig:** Entferne den gesamten `build:` Block (Zeilen 16-19) und
   behalte nur die `image:` Zeile, da wir das Image bereits gebaut haben:

   ```yaml
   services:
     zeroclaw:
       image: zeroclaw:latest       # ← nur diese Zeile behalten
       container_name: zeroclaw
       restart: unless-stopped
       # ... rest bleibt gleich
   ```

### Schritt 7: Environment-Variablen in Portainer setzen

Scrolle nach unten zu **Environment variables** → **Advanced mode**.

Pflicht:

```
ZEROCLAW_API_KEY=sk-ant-DEIN_ANTHROPIC_KEY
```

Optional (je nach gewünschten Kanälen):

```
ZEROCLAW_PORT=3000
ZEROCLAW_EMBEDDING_API_KEY=sk-DEIN_OPENAI_KEY
ZEROCLAW_TELEGRAM_TOKEN=123456789:ABCdefGHIjklMNO
ZEROCLAW_DISCORD_TOKEN=MTIz...
```

> **Vorteil gegenüber .env Dateien:** Portainer speichert die Variablen
> verschlüsselt und zeigt sie maskiert an.

### Schritt 8: Stack deployen

1. Klicke **Deploy the stack**
2. Der Container sollte in wenigen Sekunden starten (Image ist ja schon gebaut)

### Schritt 9: Prüfen ob alles läuft

In Portainer:

1. **Containers** → `zeroclaw` sollte **Running** (grün) zeigen
2. Klicke auf den Container → **Logs** → Prüfe auf Fehler
3. **Container → Console** → Wähle `/bin/bash` → Execute:
   ```bash
   zeroclaw status
   zeroclaw doctor
   ```

---

## 3. Konfiguration

### Wo liegt was?

| Was | Wo | Bearbeiten über |
|---|---|---|
| API-Keys & Secrets | Portainer → Stack → Environment | Portainer Web-UI |
| Verhalten & Kanäle | `/volume1/docker/zeroclaw/config/config.toml` | File Station oder SSH |
| Zeroclaw Quellcode | `/volume1/docker/zeroclaw/repo/` | `git pull` (nicht manuell ändern) |
| Persistente Daten | `/volume1/docker/zeroclaw/data/` | File Station (nur lesen) |
| Dockerfile | `/volume1/docker/zeroclaw/Dockerfile` | File Station oder SSH |

### config.toml bearbeiten

**Via SSH:**

```bash
sudo vi /volume1/docker/zeroclaw/config/config.toml
```

**Via File Station:**

1. File Station → `docker/zeroclaw/config/config.toml`
2. Rechtsklick → Herunterladen → Bearbeiten → Wieder hochladen

Nach Änderungen: In Portainer den Container **Restart**en.

### Environment-Variablen ändern

1. **Portainer → Stacks → zeroclaw**
2. **Editor** Tab → Environment variables bearbeiten
3. **Update the stack** klicken (Container wird automatisch neu erstellt)

### Wichtige config.toml Abschnitte

Siehe `config/config.toml.example` für die vollständige dokumentierte Referenz.

```
[provider]     → LLM-Auswahl (Modell, Provider)
[identity]     → Name und Persönlichkeit des Agenten
[memory]       → Speicher-Backend (sqlite/markdown/none)
[channels.*]   → Messaging-Kanäle aktivieren/konfigurieren
[gateway]      → HTTP-Server für Webhooks
[security]     → Autonomie-Level und Berechtigungen
[tunnel]       → Remote-Zugriff (Cloudflare/Tailscale/ngrok)
[browser]      → Browser-Automatisierung
[observer]     → Prometheus/OpenTelemetry Metriken
```

---

## 4. Betrieb & Überwachung

### Täglicher Betrieb — alles über Portainer

| Aktion | Portainer-Pfad |
|---|---|
| Status prüfen | Containers → `zeroclaw` → Status-Badge |
| Logs anschauen | Containers → `zeroclaw` → Logs |
| Neustarten | Containers → `zeroclaw` → Restart-Button |
| Stoppen | Containers → `zeroclaw` → Stop-Button |
| Shell öffnen | Containers → `zeroclaw` → Console → `/bin/bash` |
| Ressourcen | Containers → `zeroclaw` → Stats (CPU, RAM, Netzwerk) |

### Diagnostik im Container

Öffne die Console in Portainer (Container → Console → `/bin/bash`):

```bash
zeroclaw status
zeroclaw doctor
```

### Automatischer Neustart

Der Container hat `restart: unless-stopped` — er startet automatisch nach:
- NAS-Reboot
- Container-Crash
- Docker-Daemon-Neustart

---

## 5. Messaging-Kanäle einrichten

### Telegram (empfohlen für den Einstieg)

1. **Bot erstellen:**
   - Öffne Telegram, suche nach `@BotFather`
   - Sende `/newbot`, folge den Anweisungen
   - Kopiere den Bot-Token

2. **Token in Portainer eintragen:**
   - Stacks → `zeroclaw` → Environment variables
   - Hinzufügen: `ZEROCLAW_TELEGRAM_TOKEN=123456789:ABCdefGHI...`

3. **Kanal in config.toml aktivieren:**
   ```toml
   [channels.telegram]
   enabled = true
   ```

4. **Stack updaten** (Portainer → Update the stack)

5. **Testen:** Sende deinem Bot eine Nachricht in Telegram

> **Polling vs. Webhook:** Ohne HTTPS-Zugang nutzt Zeroclaw automatisch
> Long-Polling — kein Reverse Proxy nötig für den Einstieg.

### Discord

1. Bot auf https://discord.com/developers/applications erstellen
2. Bot-Token kopieren, `MESSAGE_CONTENT` Intent aktivieren
3. Bot zu deinem Server einladen (OAuth2 → bot Scope)
4. In Portainer: `ZEROCLAW_DISCORD_TOKEN=MTIz...`
5. In config.toml: `[channels.discord]` → `enabled = true`
6. Stack updaten

### Slack

1. App auf https://api.slack.com/apps erstellen
2. Bot Token und App Token generieren
3. Event Subscriptions aktivieren
4. In Portainer alle drei Tokens setzen
5. In config.toml: `[channels.slack]` → `enabled = true`
6. Stack updaten

### WhatsApp, Matrix, Email, IRC

Siehe die kommentierten Abschnitte in `config/config.toml.example` und
die entsprechenden Environment-Variablen in der `docker-compose.yml`.

---

## 6. Updates

Das ist der große Vorteil des Repo-Ansatzes: Updates sind ein einfaches
`git pull` + Image-Rebuild.

### Standard-Update (3 Befehle)

Per SSH auf der NAS:

```bash
cd /volume1/docker/zeroclaw/repo

# 1. Neuesten Code holen
sudo git pull

# 2. Image neu bauen
cd ..
sudo docker build -t zeroclaw:latest --no-cache -f Dockerfile repo/

# 3. Container neu starten (Portainer erkennt das neue Image)
sudo docker restart zeroclaw
```

Oder über Portainer: Containers → `zeroclaw` → **Recreate**.

### Update auf einen bestimmten Release

```bash
cd /volume1/docker/zeroclaw/repo

# Verfügbare Tags anzeigen
sudo git fetch --tags
sudo git tag -l

# Auf bestimmten Release wechseln
sudo git checkout v0.6.0

# Image bauen und Container neu starten
cd ..
sudo docker build -t zeroclaw:latest --no-cache -f Dockerfile repo/
sudo docker restart zeroclaw
```

### Zurückrollen auf eine ältere Version

```bash
cd /volume1/docker/zeroclaw/repo
sudo git checkout v0.4.0     # alte Version

cd ..
sudo docker build -t zeroclaw:latest --no-cache -f Dockerfile repo/
sudo docker restart zeroclaw
```

### Update-Checkliste

1. Backup erstellen (siehe Abschnitt 7)
2. `git pull` oder `git checkout <tag>`
3. `docker build --no-cache`
4. Container recreaten in Portainer
5. Logs prüfen (Portainer → Containers → zeroclaw → Logs)
6. `zeroclaw doctor` in der Console ausführen

---

## 7. Backup & Restore

### Was sichern?

| Was | Wo | Priorität |
|---|---|---|
| Environment-Variablen | Portainer Stack-Einstellungen | Kritisch — notiere deine Keys separat |
| config.toml | `/volume1/docker/zeroclaw/config/` | Hoch |
| SQLite-Datenbank + Secret Key | `/volume1/docker/zeroclaw/data/` | Hoch |
| Repo + Overrides | `/volume1/docker/zeroclaw/` | Niedrig — reproduzierbar via `git clone` |

### Backup erstellen

Da alle Daten direkt auf dem NAS-Dateisystem liegen (kein Docker-Volume),
ist Backup trivial:

```bash
cd /volume1/docker/zeroclaw
mkdir -p backups

# Alles Wichtige in ein Archiv
sudo tar czf backups/zeroclaw-$(date +%Y%m%d).tar.gz config/config.toml data/
```

Oder einfach per **File Station** den `data/` und `config/` Ordner kopieren.

### Restore

```bash
cd /volume1/docker/zeroclaw

# Aus Backup wiederherstellen
sudo tar xzf backups/zeroclaw-DATUM.tar.gz
```

Dann in Portainer den Container neu starten.

### Hyper Backup (empfohlen)

Da alles unter `/volume1/docker/zeroclaw/` liegt, füge einfach diesen einen
Pfad zu deinem Hyper Backup Task hinzu:

- `/volume1/docker/zeroclaw/` (schließt `config/`, `data/` und `backups/` ein)

Das `repo/`-Verzeichnis wird zwar mitgesichert, schadet aber nicht — es ist
jederzeit per `git clone` reproduzierbar.

---

## 8. Reverse Proxy (HTTPS)

Für Webhooks (Telegram Webhook-Modus, Slack, WhatsApp) brauchst du HTTPS.

### Option A: Synology Reverse Proxy (empfohlen)

1. **DSM → Systemsteuerung → Anmeldeportal → Erweitert → Reverse Proxy**
2. **Erstellen:**
   - Beschreibung: `Zeroclaw`
   - Quelle: HTTPS, `zeroclaw.deine-domain.de`, Port 443
   - Ziel: HTTP, `localhost`, Port 3000
3. **SSL-Zertifikat** einrichten:
   - DSM → Systemsteuerung → Sicherheit → Zertifikat
   - Hinzufügen → Let's Encrypt Zertifikat
   - Dem Reverse-Proxy-Eintrag zuweisen

### Option B: Zeroclaw-eigener Tunnel

In `config/config.toml`:

```toml
[tunnel]
kind = "cloudflare"
```

Und in Portainer Environment: `ZEROCLAW_TUNNEL_TOKEN=dein-token`

### Option C: Kein HTTPS (nur Polling)

Telegram und Discord funktionieren auch ohne HTTPS im Polling-Modus.
Du brauchst keinen Reverse Proxy wenn du keine Webhooks nutzt.

---

## 9. Troubleshooting

### Build schlägt fehl (Out of Memory)

**Symptom:** `error: could not compile` während `docker build`

**Lösung:** Der Rust-Build braucht ~1-2 GB RAM.

1. Stoppe andere Container während des Builds (Portainer → Containers → Stop)
2. Oder erhöhe temporär den Swap per SSH:
   ```bash
   sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
   sudo mkswap /swapfile && sudo swapon /swapfile
   # Nach dem Build:
   sudo swapoff /swapfile && sudo rm /swapfile
   ```

### Container startet nicht / restarts endlos

1. **Portainer → Containers → zeroclaw → Logs** — Fehlermeldung prüfen
2. Häufigste Ursache: Fehlender oder falscher `ZEROCLAW_API_KEY`
3. Prüfe ob die config.toml korrekt gemountet ist:
   - Container → Inspect → Mounts → config.toml sollte sichtbar sein

### "Permission denied" bei config.toml

Der Container läuft als User `zeroclaw` (nicht root). Die config.toml auf
der NAS muss lesbar sein:

```bash
sudo chmod 644 /volume1/docker/zeroclaw/config/config.toml
```

### git pull schlägt fehl

```bash
cd /volume1/docker/zeroclaw/repo

# Falls lokale Änderungen vorhanden (sollte nicht sein):
sudo git stash
sudo git pull
```

Falls das Repo beschädigt ist — einfach neu klonen:

```bash
cd /volume1/docker/zeroclaw
sudo rm -rf repo
sudo git clone https://github.com/zeroclaw-labs/zeroclaw.git repo
```

Deine Overrides (Dockerfile, config.toml, docker-compose.yml) sind nicht betroffen,
da sie außerhalb des Repos liegen.

### Webhook-Nachrichten kommen nicht an

1. Prüfe in Portainer → Container → Logs ob Requests ankommen
2. Prüfe ob Port 3000 in Portainer korrekt gemappt ist (Container → Inspect)
3. Prüfe Synology Firewall: DSM → Systemsteuerung → Sicherheit → Firewall
4. Prüfe Router-Portweiterleitung (Port 443 → NAS-IP:3000 wenn Reverse Proxy)

### Speicher wächst unkontrolliert

In Portainer:

1. **Images → Unused images** → Aufräumen
2. **Volumes → Unused volumes** → Aufräumen

Per SSH:

```bash
sudo docker system prune -f
# Alte Build-Cache Layer entfernen:
sudo docker builder prune -f
```

---

## 10. Sicherheitshinweise

### Autonomie-Level

Starte immer mit `supervised`:

```toml
[security]
autonomy = "supervised"
```

| Level | Bedeutung |
|---|---|
| `readonly` | Nur lesen, keine Aktionen |
| `supervised` | Bestätigung für sensible Aktionen nötig |
| `full` | Volle Autonomie — erst nach ausgiebigem Testen |

### API-Key-Sicherheit

- Keys nur in Portainer Environment-Variablen speichern (nicht in Dateien)
- Portainer zeigt Variablen maskiert an
- Niemals Keys in die config.toml oder ins Repo schreiben

### Netzwerk-Isolation

- Container läuft in eigenem Docker-Netzwerk (`zeroclaw-net`)
- Nur Port 3000 ist exponiert (und nur wenn nötig)
- Read-only Dateisystem im Container
- tmpfs für `/tmp` — wird bei Restart gelöscht

### Firewall (wenn Webhooks aktiv)

Erlaube in der Synology-Firewall nur die nötigen Quell-IPs:

- **Telegram:** `149.154.160.0/20` und `91.108.4.0/22`
- **Discord/Slack:** Keine feste IP-Liste — Port muss offen sein

---

## Quick Reference

### Update (per SSH)

```bash
cd /volume1/docker/zeroclaw/repo && sudo git pull && cd .. \
  && sudo docker build -t zeroclaw:latest --no-cache -f Dockerfile repo/ \
  && sudo docker restart zeroclaw
```

### Portainer-Aktionen

| Aktion | Wo in Portainer |
|---|---|
| Container starten/stoppen | Containers → `zeroclaw` → Start/Stop |
| Logs anschauen | Containers → `zeroclaw` → Logs |
| Shell im Container | Containers → `zeroclaw` → Console → `/bin/bash` |
| Env-Variablen ändern | Stacks → `zeroclaw` → Editor → Environment |
| Container neu erstellen | Containers → `zeroclaw` → Recreate |
| Ressourcenverbrauch | Containers → `zeroclaw` → Stats |
