# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Interactive backup setup tool that configures automated backups from remote servers. Two scripts cover Linux (bash) and Windows (PowerShell), with three transfer protocols: rsync+SSH, SFTP, and FTP.

## Architecture

Both scripts follow the same 7-step interactive flow:

1. **Protocol selection** — rsync+SSH (Linux only), SFTP, or FTP
2. **Dependency check** — installs protocol-specific packages (Linux: auto-detect pkg manager; Windows: checks for OpenSSH)
3. **Server details** — IP/hostname, credentials, port; connection test
4. **What to backup** — rsync mode: auto-discovers databases, Docker configs, existing backup dirs. SFTP/FTP mode: manual path entry only (no remote command execution)
5. **Where + schedule** — local path, cron schedule (Linux) or Task Scheduler (Windows), retention days
6. **Authentication** — SSH key generation + deployment (rsync/SFTP) or stored FTP credentials
7. **Generate backup script + first run** — creates `run_backup.sh`/`.ps1` with protocol-specific transfer commands

Key constraint: SFTP and FTP cannot execute remote commands, so database dumps and Docker discovery are only available in rsync+SSH mode.

## Files

- `backup-setup.sh` — Linux setup script (bash). Generates `run_backup.sh` + cron job
- `backup-setup.ps1` — Windows setup script (PowerShell). Generates `run_backup.ps1` + Scheduled Task
- `README.md` — Documentation in Slovenian

## Language

All user-facing text (prompts, messages, README) is in **Slovenian**. Keep this consistent when modifying.

## Testing

No automated tests. To test, run the scripts interactively against a test server:

```bash
# Linux
chmod +x backup-setup.sh && ./backup-setup.sh

# Windows (PowerShell as Administrator)
PowerShell -ExecutionPolicy Bypass -File backup-setup.ps1
```

## Protocol-Specific Transfer Commands

- **rsync**: `rsync -avz --delete` over SSH — incremental, supports `--delete`
- **SFTP**: `sftp -r get` with batch mode (Linux), `sftp.exe -b` (Windows) — no delete/mirror
- **FTP Linux**: `lftp mirror --delete` — supports mirror with delete
- **FTP Windows**: Recursive download via `System.Net.FtpWebRequest` (.NET) — no delete/mirror
