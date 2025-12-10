# Nextcloud Docker Generator

Interaktives Shell-Skript zur Bereitstellung von Multi-Tenant Nextcloud mit Caddy für automatisches HTTPS.

**[English Guide / Englische Anleitung](README.md)**

## Funktionen

- Automatisches HTTPS via Caddy (Let's Encrypt)
- PostgreSQL 15 Datenbank pro Instanz
- Redis 7 Caching pro Instanz
- Nginx für PHP-FPM Optimierung
- Unterstützung mehrerer Nextcloud-Instanzen
- Isolierte Backend-Netzwerke
- Automatisch generierte sichere Passwörter

---

## Vollständige Einrichtungsanleitung (Ubuntu 24.04 LTS)

Diese Anleitung führt Sie durch die Einrichtung eines frischen Ubuntu 24.04 LTS Servers für Nextcloud-Hosting.

### 1. Grundlegende Server-Einrichtung

```bash
# System aktualisieren
sudo apt update && sudo apt upgrade -y

# Wichtige Tools installieren
sudo apt install -y curl wget git htop nano ufw
```

### 2. Firewall konfigurieren

```bash
# SSH, HTTP und HTTPS erlauben
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Firewall aktivieren
sudo ufw enable

# Status überprüfen
sudo ufw status
```

### 3. Sekundäre Festplatte mit LVM konfigurieren

Die meisten Server haben eine kleine OS-Festplatte und eine größere Daten-Festplatte. Wir konfigurieren die Daten-Festplatte mit LVM für mehr Flexibilität.

```bash
# Verfügbare Festplatten anzeigen
lsblk

# Identifizieren Sie Ihre sekundäre Festplatte (z.B. /dev/sdb oder /dev/vdb)
# ACHTUNG: Dies löscht alle Daten auf der Festplatte!

# LVM-Tools installieren
sudo apt install -y lvm2

# Physical Volume erstellen (ersetzen Sie /dev/sdb mit Ihrer Festplatte)
sudo pvcreate /dev/sdb

# Volume Group mit Namen 'data-vg' erstellen
sudo vgcreate data-vg /dev/sdb

# Logical Volume mit 100% des verfügbaren Speicherplatzes erstellen
sudo lvcreate -l 100%FREE -n data-lv data-vg

# Mit ext4 formatieren
sudo mkfs.ext4 /dev/data-vg/data-lv

# Mount-Punkt erstellen
sudo mkdir -p /srv

# UUID des neuen Volumes ermitteln
sudo blkid /dev/data-vg/data-lv

# Zu /etc/fstab hinzufügen für persistenten Mount (UUID mit echtem Wert ersetzen)
echo "UUID=IHRE-UUID-HIER /srv ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Volume mounten
sudo mount -a

# Mount überprüfen
df -h /srv
```

### 4. Docker installieren

```bash
# Docker mit offiziellem Skript installieren
curl -fsSL https://get.docker.com | sudo sh

# Benutzer zur docker-Gruppe hinzufügen (Logout/Login erforderlich)
sudo usermod -aG docker $USER

# Docker beim Systemstart aktivieren
sudo systemctl enable docker

# Docker starten
sudo systemctl start docker

# Aus- und wieder einloggen, dann überprüfen
docker --version
docker ps
```

### 5. Docker-Daten nach /srv verschieben

Standardmäßig speichert Docker Daten in `/var/lib/docker`. Wir verschieben sie nach `/srv` für mehr Speicherplatz.

```bash
# Docker stoppen
sudo systemctl stop docker

# Docker-Verzeichnis auf Daten-Festplatte erstellen
sudo mkdir -p /srv/docker

# Bestehende Docker-Daten verschieben (falls vorhanden)
sudo rsync -avxP /var/lib/docker/ /srv/docker/

# Docker für neuen Speicherort konfigurieren
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/srv/docker"
}
EOF

# Alte Docker-Daten entfernen (optional, nach Überprüfung)
sudo rm -rf /var/lib/docker

# Docker starten
sudo systemctl start docker

# Neuen Speicherort überprüfen
docker info | grep "Docker Root Dir"
```

### 6. DNS konfigurieren

Bevor Sie das Skript ausführen, stellen Sie sicher, dass Ihre Domain(s) auf Ihren Server zeigen:

1. Gehen Sie zu Ihrem DNS-Anbieter
2. Erstellen Sie einen A-Record für jede Nextcloud-Instanz:
   - `cloud.beispiel.de` → `IHRE_SERVER_IP`
   - `dateien.beispiel.de` → `IHRE_SERVER_IP`
3. Warten Sie auf die DNS-Propagierung (kann bis zu 24h dauern, meist nur Minuten)

DNS überprüfen:
```bash
dig +short cloud.beispiel.de
curl -s ifconfig.me
# Beide sollten dieselbe IP anzeigen
```

### 7. Nextcloud bereitstellen

```bash
# Zum Daten-Laufwerk navigieren
cd /srv

# Deployment-Skript herunterladen und ausführen
curl -fsSL https://raw.githubusercontent.com/gstohl/nextcloud-docker-generator/main/deploy-nextcloud.sh -o deploy-nextcloud.sh
chmod +x deploy-nextcloud.sh
./deploy-nextcloud.sh
```

Das Skript fragt Sie nach:
- **Projektverzeichnis**: Wo Konfigurationen gespeichert werden (z.B. `nextcloud`)
- **ACME-E-Mail**: Für Let's Encrypt Zertifikatsbenachrichtigungen
- **Anzahl der Instanzen**: Wie viele Nextcloud-Seiten
- **Domain pro Instanz**: z.B. `cloud.beispiel.de`
- **Admin-Benutzername pro Instanz**: Standard ist `admin`

### 8. Nach der Installation

Nach der Bereitstellung:

```bash
# Container-Status prüfen
cd /srv/nextcloud  # oder Ihr Projektverzeichnis
./manage.sh status

# Logs anzeigen
./manage.sh logs

# Caddy-Logs anzeigen (bei SSL-Problemen)
./manage.sh logs caddy
```

**Zugangsdaten** werden in `credentials.txt` gespeichert - sicher aufbewahren und Datei löschen!

---

## Verwaltungsbefehle

```bash
./manage.sh status              # Container-Status prüfen
./manage.sh logs [service]      # Logs anzeigen
./manage.sh restart [service]   # Service neu starten
./manage.sh fix-permissions     # Dateiberechtigungen reparieren
./manage.sh occ1 [befehl]       # occ auf Instanz 1 ausführen
```

## Fehlerbehebung

### SSL-Zertifikat-Probleme
```bash
# Caddy-Logs prüfen
docker logs caddy

# Überprüfen ob Ports offen sind
curl -v http://ihre-domain.de
```

### 403 Forbidden Fehler
```bash
./manage.sh fix-permissions
./manage.sh restart
```

### Speicherplatz prüfen
```bash
df -h /srv
docker system df
```

### Docker aufräumen
```bash
# Ungenutzte Images und Container entfernen
docker system prune -a
```

## Backup

```bash
# Alle Daten sichern
cd /srv/nextcloud
docker compose stop
sudo tar -czvf /backup/nextcloud-$(date +%Y%m%d).tar.gz .
docker compose start
```

## Lizenz

MIT
