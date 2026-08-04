- [WebDAV / Nextcloud](#webdav--nextcloud)
- [Existing rclone remote](#existing-rclone-remote)
- [Local folder](#local-folder)
- [First-run auto-wizard](#first-run-auto-wizard)

The setup wizard is invoked by `:Obsidian sync setup`, `:ObsidianSync` (when no vaults are linked), or automatically on first launch.

## WebDAV / Nextcloud

```
Configure rclone sync for my-vault
  1. WebDAV / Nextcloud (connect directly)
  2. Use an existing rclone remote
  3. Run rclone config to add a new remote
  4. Sync with a local folder (two-way)
```

Choose **1** → pick server type:

```
Select WebDAV server type
  1. Nextcloud / ownCloud
  2. Generic WebDAV
```

Nextcloud/ownCloud auto-sets `vendor = nextcloud` for rclone.  Then enter credentials:

```
WebDAV URL: https://my-nextcloud.example.com/remote.php/dav/files/user/MyVault/
Username:    myuser
Password:    ********
```

The plugin runs internally:

```bash
rclone config create obsidian-sync-my-vault webdav \
  url=... user=... pass=... vendor=nextcloud --non-interactive --obscure
```

The password is written to `~/.config/rclone/rclone.conf` **obscured** (not plaintext).  It never appears in Neovim's data files.

Optionally enter a sub-path if your vault lives inside a folder on the WebDAV root:

```
Remote sub-path (e.g. vault/main, <CR> for root):
```

Finally:

```
Linked my-vault <-> obsidian-sync-my-vault:
Start syncing now?  Yes
```

The mapping is persisted to `stdpath("data")/obsidian-sync.json`.

## Existing rclone remote

If you already have remotes in `rclone.conf` (S3, SFTP, etc.), pick **2**:

```
Select rclone remote
  mys3:
  backup-webdav:
```

Choose a remote, then optionally enter a sub-path.  The vault is linked to `remote:path`.

## Local folder

Pick **4** → enter an absolute path.  Two-way sync between two local directories.  Useful for testing, or syncing with an external drive.

## First-run auto-wizard

When the plugin loads and no vaults are linked (empty `obsidian-sync.json`), it shows a dialog on `VimEnter`:

```
┌────────────────────────────────────────┐
│  obsidian-sync: No vaults linked yet.  │
│  Run the setup wizard now?             │
│                                        │
│  Yes  ← (default)                      │
│  No                                    │
└────────────────────────────────────────┘
```

For lazy-loaded obsidian.nvim (`ft = "markdown"`), the wizard fires on `User ObsidianWorkpspaceSet` — i.e. when you first open a `.md` file.

Answering **No** shows a hint: `Run :ObsidianSync or :Obsidian sync setup later.`
