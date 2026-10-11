# Information

- https://github.com/tech-otaku/hetzner-cloud-init/blob/main/config.yaml
- https://community.hetzner.com/tutorials/basic-cloud-config
- https://cloudinit.readthedocs.io/en/latest/index.html
- https://community.hetzner.com/tutorials/securing-ssh


```yaml
#include
https://raw.githubusercontent.com/kaijen/hetzner-cloud-init/refs/heads/main/hetzner-small.yml
```

```yaml
#include
https://raw.githubusercontent.com/kaijen/hetzner-cloud-init/refs/heads/main/hetzner-master.yml
```

```yaml
#include
https://raw.githubusercontent.com/kaijen/hetzner-cloud-init/refs/heads/main/hetzner-test.yml
```

```yaml
#include
https://raw.githubusercontent.com/kaijen/hetzner-cloud-init/refs/heads/main/hetzner-jinja.yml.jinja
```



## Agent-Server

`hetzner-agent.yml.jinja` richtet einen Server für Agentenaufgaben mit Claude Code ein: Ubuntu 24.04, ausgelegt auf Hetzner CAX (arm64), läuft auch auf x86.

Der Server bekommt den Benutzer `kai` mit sudo ohne Passwort und genau einem SSH-Schlüssel, pyenv mit Python 3.14 und der virtuellen Umgebung `claude-code`, Rust über rustup, Go von go.dev, nvm mit dem neuesten Node-LTS, git, gh, Claude Code und `kanban-md`. Docker stammt aus dem Repository von Docker. Traefik nimmt auf Port 80 und 443 an und holt Zertifikate per HTTP-01; das Dashboard liegt hinter Authelia mit TOTP.

### Vor dem Einsatz

Die Werte unter `ANPASSEN` am Kopf der Datei setzen: Hostname, FQDN, Basisdomain, ACME-Adresse. Den Inhalt der Datei vollständig als Userdata einfügen; die erste Zeile `## template: jinja` muss die erste Zeile der Userdata bleiben.

Vor dem Start DNS-Einträge auf die Server-IP setzen, mindestens für `auth.<domain>` und `traefik.<domain>`, dazu einen je Dienst, etwa `kaimarkit.<domain>`. Ohne Eintrag scheitert HTTP-01, und Let's Encrypt begrenzt fehlgeschlagene Versuche.

Die Einrichtung dauert auf einer kleinen CAX-Instanz rund 15 Minuten, den größten Teil davon baut pyenv Python. Fortschritt und Fehler stehen in `/var/log/cloud-init-output.log`. Verlangt ein Paket-Upgrade einen Neustart, startet der Server am Ende neu.

### Nach dem ersten Login

In die Userdata gehören keine Geheimnisse, jeder Prozess auf dem Server kann sie über den Metadatendienst lesen. Anmeldungen laufen deshalb von Hand:

```bash
gh auth login                 # GitHub für git und gh
claude                        # Claude Code anmelden
authelia-add-user kai <mail>  # fragt nach dem Passwort, startet Authelia
sudo cat /srv/proxy/authelia/config/notification.txt   # Code für TOTP
```

Die Authelia-Schlüssel erzeugt der Server beim ersten Start selbst unter `/srv/proxy/authelia/secrets`.

### VSCode

Remote-SSH braucht Port-Forwarding. Die SSH-Härtung erlaubt deshalb `AllowTcpForwarding local`; Agent-Forwarding bleibt aus. Eintrag in `~/.ssh/config`:

```
Host agent
    HostName agent.example.com
    User kai
    IdentityFile ~/.ssh/id_ed25519
```

### Dienste hinter Traefik

Der Stack liegt unter `/srv/proxy`. Netz, Entrypoint und Certresolver heißen wie die Vorgaben in `kaimarkit/docker/.env.example`: `traefik-web`, `websecure`, `myresolver`. Die Middleware von Authelia heißt `authelia@docker`. Für kaimarkit genügt deshalb in `docker/.env`, die Domain zu setzen:

```bash
KAIMARKIT_DOMAIN=kaimarkit.<domain>
AUTHELIA_VERIFY_URL=http://authelia:9091/api/verify?rd=https://auth.<domain>
```

Start mit Traefik und Authelia:

```bash
docker compose -f docker/docker-compose.yml \
               -f docker/docker-compose.traefik.yml \
               -f docker/docker-compose.authelia.yml up -d --build
```
