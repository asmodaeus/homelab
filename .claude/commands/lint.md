# /lint — Lokale Linter ausführen

Führe alle drei Linter für dieses Repo aus und berichte das Ergebnis.

## Schritte

1. **yamllint** — alle YAML-Dateien:
   ```bash
   yamllint .
   ```

2. **ansible-lint** — Ansible Playbooks und Roles:
   ```bash
   ANSIBLE_ROLES_PATH="ansible/roles:~/.ansible/roles" \
   ANSIBLE_CONFIG="ansible/ansible.cfg" \
   ansible-lint ansible/
   ```

3. **kube-linter** — Kubernetes Manifeste:
   ```bash
   kube-linter lint . --config .kube-linter.yaml
   ```

Zeige für jeden Linter ob er bestanden hat oder welche Fehler aufgetreten sind.
Fasse am Ende zusammen: wie viele Linter sind grün, welche haben Fehler.

Falls ein Tool nicht installiert ist, weise darauf hin und überspringe es.
