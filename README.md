# Cloned Machine Identity — Agent Skill

An [agent skill](https://github.com/anthropics/skills) for sanitizing a Linux
machine that was created from a disk image.

A restored image is a byte-for-byte copy of a filesystem, and that includes the
files that identify *which machine this is*. Restore one onto different
hardware and you get a working system still carrying the source machine's
machine-id, hostname, and journal.

This is not an edge case. Restoring an image to a laptop is the intended
workflow, and every restore does this.

## The skill

### `cloned-machine-identity`

- Telling a **clone** apart from the **source** machine and from a **fresh
  install** — only the first needs fixing, and the source is the one that looks
  most affected
- Detecting a clone from a stale hostname and inherited journal
- Regenerating a duplicate machine-id
- Fixing a hostname that names the wrong laptop
- Clearing logs carried over from the source machine
- SSH host key checks — when there is nothing to regenerate
- Rolling the fix across a fleet and proving the IDs are distinct

Two scripts ship with it:

| Script | Risk | Purpose |
|---|---|---|
| `survey-fleet-identity.sh` | Read-only, no root | Classify every machine as source, clone, or unique |
| `fix-cloned-machine-identity.sh` | **Destructive** | Apply the fix — hostname, machine-id, journal |

Survey first. The survey is safe on any machine, including ones that need no
work; the fix is not.

## Why this exists

Found on Omarchy (Arch/Hyprland) on an HP Pavilion 15, restored via the
Rescuezilla clone feature from an image of a Lenovo T440p. The restored system
booted cleanly, reported the correct hardware from DMI, and was still calling
itself `lenovot440p` with that machine's machine-id and eight days of its logs.

Nothing in a normal boot process checks these files, which is why the problem
survives an otherwise successful restore.

| Trap | Consequence |
|---|---|
| Running the fix on the source machine | Renames a healthy machine, wipes its real journal |
| `systemd-machine-id-setup` on an existing file | Exits 0, changes nothing, ID stays duplicated |
| `journalctl --vacuum-time=1s` | Not selective — discards the current machine's logs too |
| Assuming a fresh USB install is a clone | Nothing was inherited; nothing to fix |

## Installation

```bash
git clone https://github.com/ssearles/cloned-machine-identity.git
cp -r cloned-machine-identity/skills/* ~/.agents/skills/
```

Skills live in `~/.agents/skills/`. The `description` field in the YAML
frontmatter determines when an agent loads it, so it is written as trigger
vocabulary.

For a one-off on a machine you are sitting at, the fix alone is enough:

```bash
sudo ./skills/cloned-machine-identity/fix-cloned-machine-identity.sh <new-hostname>
```

## Confidence markers

Claims are tagged throughout:

- **`[PROVEN]`** — directly observed and diagnosed on real hardware
- **`[INFERRED]`** — concluded from output, not isolated in a controlled test

The distinction matters: some guidance is established by measurement, some is
reasoned from symptoms. Treat them accordingly.

## Requirements

Linux with `systemd` (`systemd-machine-id-setup`), `journalctl`, and Python 3
for the survey's journal-hostname probe. Root for the fix, none for the survey.

No sudo is needed for diagnosis, which is deliberate — the read-only checks are
safe on any machine, including the source.

## Related

Companion to [`disk-backup-skills`](https://github.com/ssearles/disk-backup-skills),
which covers the imaging workflow these problems come from.

## Licence

MIT — use, modify, redistribute freely.
