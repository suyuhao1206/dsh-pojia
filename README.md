# dsh-pojia

Jailbreak / cleaning plugin for the DeepSeek Harness: works with every model, swap prompts per model. Cleaning + a cybersecurity drill console in one.

- **Target**: DeepSeek Harness **0.2.2-rc.3** (official desktop EXE), plugin **1.0.1** or newer. Older dsh builds need the matching older plugin.
- **Desktop only.** This build does not cover the Web host (`dsh web`).

---

## Deploy (desktop, Windows)

**No `dsh` command, no Node, no pnpm needed.** Pick one of the three install paths below; installing does **not** patch the host by itself, so finish the three first-run steps afterwards.

### Option 1: install from the host UI (recommended, no terminal)

Desktop app → **Plugins** in the sidebar → **Add plugin** → paste the **absolute path** of this plugin folder (for example `D:\apps\dsh-pojia`) → install → fully quit and reopen.

> The old `install.cmd` / `scripts\install-desktop.ps1` installers are gone. The `dsh` command is now installed by the client itself via **menu → Manage dsh command…**; the plugin no longer drops `dsh.cmd` / `dsh.ps1` / `dsh` shims into PATH. Shims left behind by older versions are cleaned up on the next Apply / Revert / Uninstall.

### Option 2: if `dsh` is already available

```sh
cd <this directory>
dsh plugin --profile desktop add .
```

Install `dsh` from the desktop app's **Manage dsh command…** menu; the plugin does not handle that any more.

### Option 3: manual wiring (troubleshooting)

1. Locate the `$DSH_HOME` in use (`%USERPROFILE%\.dsh`; it must contain `profiles\`).
2. Put the plugin folder at `$DSH_HOME\plugins\dsh-pojia` (any other location works too, point the link at it).
3. Create a junction / directory link at `$DSH_HOME\profiles\desktop\node_modules\dsh-pojia` pointing to step 2.
4. Edit `$DSH_HOME\profiles\desktop\package.json`:
   - add `"dsh-pojia": "link:<plugin folder, forward slashes>"` to `dependencies`
   - append `"dsh-pojia"` to `dsh.profile.bundles` (no duplicates, JSON must stay valid)
5. **No `pnpm install` required** — the link is enough for the host to resolve the plugin.

The old instructions (copy into `node_modules`, then `pnpm install`) are gone: they were a dead end for anyone without pnpm.

### Migrating from dsh-purge

1. Uninstall the old plugin first (sidebar → Uninstall, or `/purge uninstall` in chat) to restore the host files.
2. Quit the desktop app completely (including the tray), then install `dsh-pojia` as above.

### First run — three steps

1. **Fully quit and reopen** the desktop app.
2. Click **dsh-pojia** beside the session title → **Clean** → **Apply**.
3. A successful Apply restarts the host once; after the restart, **start a new chat** so the inject enters the session.

---

## Usage

### Chat commands

```text
/pojia status | apply | revert | uninstall | edit | help
/rules list | use <id> | create <id> [alias] [target] | delete <id> | reset | help
/skills list | import <zip|folder> | create <id> [description] | delete <id> | help
/rewind once | round
```

### Model tools

```text
pojia_status   pojia_apply   pojia_revert
```

### CLI

```sh
dsh-pojia --status     # show status
dsh-pojia --apply      # apply all patches
dsh-pojia --revert     # revert to backups
dsh-pojia --uninstall  # uninstall (reverts first)
dsh-pojia --edit       # edit the inject file prompt-inject.md
```

### Sidebar (the dsh-pojia button beside the session title)

| Area | What it does |
| --- | --- |
| Clean | grouped patch status and apply, prompt editor, rule sets, skills, own servers |
| Prompt | edits `prompt-inject.md`, the per-turn override with the highest priority |
| Rules | multiple AGENTS.md / CLAUDE.md sets; enabling writes into `$DSH_HOME`; workspace rules join the injection under the `strict / fallback / always` policy |
| Skill | imports zips / folders into the official skills dir `$DSH_HOME\skills\<id>\SKILL.md`; matching, loading and `/<name>` are handled by DSH |
| Own servers | registers your own servers (written to `$DSH_HOME\net-scope-allow.txt`) to relax the network fence |
| Drill console | authorized red-team console: red-team preset (five-role pipeline), SQLite asset store, 17 bundled skills, environment adaptation, engagement reports |

### Drill console authorization and fence

- First entry: read the full notice → countdown → scroll to the bottom → check all three boxes → confirm. The grant is stored in `$DSH_HOME\dsh-purge\drill-grant.json`.
- Network: CN/HK/MO ranges are denied by default; the only exception is the one server registered under "Own servers". Verbal claims and keys never unlock anything.

---

## Revert and uninstall

- Every patched host file is backed up as `*.dshpurge.bak` before applying; Revert / `/pojia revert` restores from those backups.
- `prompt-inject.md` is a user file and is kept on revert.
- Uninstall = revert patches → remove inject and rules → delete plugin files; restart the desktop app afterwards.

## How it works (short)

Apply: back up host originals → replace files inside the `@deepseek-ai` packages per the patch table → inject the shim → write the prompt override. Every turn then hangs the prompt at the head of the system prompt. Changes only touch your own local install; after an upgrade, unmatched patches show as skipped and are never rewritten blindly.

Runtime data: `$DSH_HOME\prompt-inject.md`, `$DSH_HOME\rules\`, `$DSH_HOME\skills\`, `$DSH_HOME\net-scope-allow.txt`, `$DSH_HOME\redteam\`, `$DSH_HOME\dsh-purge\` (state).

## Upgrade

- **One-click inside the plugin**: **dsh-pojia** beside the session title → **Clean** → **Version & updates** → **Check for updates** → upgrade when a newer build shows up. It pulls from `master` of this repository (`https://github.com/suyuhao1206/dsh-pojia`), replacing `lib`, `bin`, `docs`, `presets`, `skills` and the root files, then re-applies patches and restarts.
- **Manual**: unpack the new build over the plugin folder → fully quit and reopen (no installer script any more; the plugin is already registered in the profile).

> Builds before 1.0.2 shipped `REPO = "local/dsh-pojia"` as a placeholder, so the update check always failed; overwrite once with this build and one-click upgrade starts working.

## Scope of use

Use only on your own or written-authorized local environments, offline targets, and compliant exercises. No unauthorized penetration testing and no illegal use. The drill console requires completing the notice authorization first.
