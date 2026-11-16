# dsh-pojia

Jailbreak / cleaning plugin for the DeepSeek Harness: works with every model, swap prompts per model. Cleaning + a cybersecurity drill console in one.

- **Target**: DeepSeek Harness **0.2.2-rc.3** (official desktop EXE), plugin **1.0.1** or newer. Older dsh builds need the matching older plugin.
- **Desktop only.** This build does not cover the Web host (`dsh web`).

---

## Deploy (desktop)

Node.js ≥ 18. Installing the plugin does **not** patch the host by itself — finish the three first-run steps below.

### Option 1: install from this directory (recommended)

```sh
cd <this directory>
dsh plugin --profile desktop add .
```

### Option 2: manual install

1. Locate the `$DSH_HOME` actually in use (`%USERPROFILE%\.dsh` on this machine; it must contain `profiles\`).
2. Copy this whole directory to `$DSH_HOME\profiles\desktop\node_modules\dsh-pojia` (the folder name must be `dsh-pojia`).
3. Edit `$DSH_HOME\profiles\desktop\package.json`:
   - add `"dsh-pojia": "file:../../plugins/dsh-pojia"` to `dependencies`
   - append `"dsh-pojia"` to the end of `dsh.profile.bundles` (no duplicates, JSON must stay valid)
4. Run `pnpm install` inside `$DSH_HOME\profiles\desktop`.

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

1. Fully quit the desktop app.
2. Overwrite `$DSH_HOME\profiles\desktop\node_modules\dsh-pojia` with the new contents (or re-run `dsh plugin --profile desktop add .`).
3. Start → Clean → Apply → auto restart → new chat.

The built-in update check points at no repository by default; to enable one, set `REPO` at the top of `lib/update.js` to your own `owner/repo`.

## Scope of use

Use only on your own or written-authorized local environments, offline targets, and compliant exercises. No unauthorized penetration testing and no illegal use. The drill console requires completing the notice authorization first.
