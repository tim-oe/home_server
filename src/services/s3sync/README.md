# s3sync

Weekly Restic backup of the work tree on the NAS (`/mnt/backup/work` by default) to a private AWS S3
bucket created with [`src/bin/s3-bucket.sh`](../../bin/s3-bucket.sh). Restic runs on this server and
reads the NAS mount. The NAS does not get the work AWS credentials.

VirtualBox VM folders (`.vdi`, `.vbox`, snapshots) are included. Restic stores them as
content-addressed chunks, so a later backup uploads only the chunks a used disk changed. The first
run still uploads the whole tree. An interrupted run is resumed by starting the same backup again:
chunks recorded since the last index save (about every 10 minutes, or 50 GiB) are kept. There is
nothing to restore until one run finishes and writes a snapshot.

## Host configuration

Add to the host `/etc/environment` (any local user can read this file; the IAM user is scoped
to one bucket only). The container bind-mounts that file; `s3-push.sh` reads it on every run
because busybox **crond does not pass Docker `env_file` variables into cron jobs**.

| Variable | Example | Purpose |
|----------|---------|---------|
| `EST_BACKUP_SRC` | `/mnt/backup/work` | Host path bind-mounted read-only at `/data` |
| `EST_BACKUP_BUCKET` | `tec-backup-744686699669-us-west-2-an` | Full bucket name printed by `s3-bucket.sh` |
| `EST_BACKUP_AWS_REGION` | `us-west-2` | Region for the S3 repository URL |
| `EST_BACKUP_ID` | | IAM user `aws_access_key_id` |
| `EST_BACKUP_KEY` | | IAM user `aws_secret_access_key` |
| `RESTIC_PASSWORD` | | Encrypts the repository. Losing it loses the backups |

Optional: `GOTIFY_APP_TOKEN` (same app token as other backup stacks—not Grafana’s `GOTIFY_TOKEN`
in `grafana/.env`), `KEEP_WEEKLY` (default 4).

Once the NAS path is mounted and populated:

```bash
touch /mnt/backup/work/.s3sync-sentinel
```

The backup refuses to run if that file is missing, so an empty mountpoint cannot be recorded as
an empty snapshot that later forgets the real history.

**Quiet period:** have the work backup job `rm -f /mnt/backup/work/.backup-complete` at the start
and `touch /mnt/backup/work/.backup-complete` when it finishes. The push skips while that marker
is missing (backup running) or was touched within `QUIET_MINUTES` (default 30). A full-tree
`find` over large VM trees is intentionally not used.

List snapshots without starting a backup:

```bash
docker exec -e SNAPSHOTS_ONLY=1 s3sync /bin/sh /s3-push.sh
```

A manual backup before the marker workflow exists:

```bash
docker exec -e SKIP_QUIET=1 s3sync /bin/sh /s3-push.sh
```

Progress during long runs: `docker logs -f s3sync`.

## Bucket setup

1. Create the bucket and tie it to one IAM user. The script prints the full account-regional name:

   ```bash
   ./src/bin/s3-bucket.sh --region us-west-2 tec-backup arn:aws:iam::744686699669:user/NAME
   ```

2. Create an access key for that user and set `EST_BACKUP_ID` / `EST_BACKUP_KEY`.

3. Leave bucket versioning off. Restic snapshots are the history. Versioning would keep every pack
   that `forget --prune` deletes. If versioning was turned on for the earlier whole-file copy,
   suspend it:

   ```bash
   aws s3api put-bucket-versioning --bucket "$BUCKET" --region "$REGION" \
     --versioning-configuration Status=Suspended
   ```

4. Abort unfinished multipart uploads. As an account admin:

   ```bash
   aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --region "$REGION" \
     --lifecycle-configuration '{
       "Rules": [
         {
           "ID": "abort-incomplete-multipart",
           "Status": "Enabled",
           "Filter": {},
           "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 3 }
         }
       ]
     }'
   ```

Objects are stored as `STANDARD`. Infrequent Access charges a 30-day minimum and a retrieval fee
when prune rewrites packs. Whole-file objects from the earlier rclone upload are not a Restic
repository; delete them after this stack is in place if they are still in the bucket.

## Deploy and run

Stop the rclone upload first so it does not share the uplink. Recreate the container so it
switches to the Restic image and the cache volume:

```bash
./gradlew deployS3sync
# on the host, under /mnt/raid/services/s3sync:
docker compose up -d
```

Manual backup:

```bash
docker exec -e SKIP_QUIET=1 s3sync /bin/sh /s3-push.sh
```

Test Gotify (silent on success; `gotify OK` means the message was accepted):

```bash
docker exec s3sync sh -c '. /gotify-notify.sh; gotify_notify 5 "s3sync test" "ping" && echo gotify OK || echo gotify FAIL'
```

## Browse and restore

[Backrest](https://github.com/garethgeorge/backrest) runs in this stack and is the UI for the same
repository. It does not take backups and it must not run forget or prune; `s3-push.sh` owns that.

`https://backrest.tecronin.uk` is LAN-only (and WireGuard). Add an Unbound host override on
OPNsense: `backrest.tecronin.uk` → `192.168.1.35`. The first visit asks you to create the Backrest
login. That login is separate from `RESTIC_PASSWORD`.

Add the existing repository. Do not add a backup plan. Turn off the repository forget/prune
schedule.

| Field | Value |
|-------|--------|
| URI | `s3:s3.<region>.amazonaws.com/<bucket>` (same URL `s3-push.sh` prints) |
| Password | Leave blank. The container already has `RESTIC_PASSWORD`. A password typed here replaces it. |
| Environment | Leave empty. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION` are mapped from `EST_BACKUP_*`. |

Snapshots appear after a backup run finishes. Paths start at `/data`, so `latop/shares` is
`/data/latop/shares`. Restore into `/restore`. Those files are on the host at `/mnt/backup/restore`.

## Schedule

Crontab inside the container: `30 1 * * 6` (Saturday 01:30, weekly). A skipped run is not retried
until the following Saturday; run `docker exec s3sync /bin/sh /s3-push.sh` to catch up by hand. Overlapping runs are skipped (file lock).
Runs are skipped when `.backup-complete` is missing or newer than `QUIET_MINUTES`. After each
finished snapshot, `restic forget --keep-weekly 4 --prune` drops older weeks. Prune does not run
when the backup itself fails, so an interrupted upload is not deleted before the next run can
reuse it.
