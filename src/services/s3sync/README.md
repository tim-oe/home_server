# s3sync

Nightly one-way push of the work backup tree on the NAS (`/mnt/backup/work` by default) to a
private AWS S3 bucket created with [`src/bin/s3-bucket.sh`](../../bin/s3-bucket.sh). Large
VirtualBox VM folders (`.vdi`, `.vbox`, snapshots) are included; rclone is tuned for multi-GB
uploads.

## Host configuration

Add to the host `/etc/environment` (any local user can read this file; the IAM user is scoped
to one bucket only). The container bind-mounts that file; `s3-push.sh` reads `EST_BACKUP_*`
from it on every run because busybox **crond does not pass Docker `env_file` variables into
cron jobs** (only `PATH` from the crontab). `docker exec` may also lack keys if the container
was created before the vars were added—reading the mount avoids both issues.

| Variable | Example | Purpose |
|----------|---------|---------|
| `EST_BACKUP_SRC` | `/mnt/backup/work` | Host path bind-mounted read-only at `/data` |
| `EST_BACKUP_BUCKET` | `tec-backup-744686699669-us-west-2-an` | Full bucket name |
| `EST_BACKUP_AWS_REGION` | `us-west-2` | Region for the S3 remote |
| `EST_BACKUP_ID` | | IAM user `aws_access_key_id` |
| `EST_BACKUP_KEY` | | IAM user `aws_secret_access_key` |

Optional: `GOTIFY_APP_TOKEN` (same rclone app token as other backup stacks—not Grafana’s
`GOTIFY_TOKEN` in `grafana/.env`), `BWLIMIT` (e.g. `08:00,20M 18:00,off`).

Once the NAS path is mounted and populated:

```bash
touch /mnt/backup/work/.s3sync-sentinel
```

The push refuses to run if that file is missing, so an empty mountpoint cannot trigger a bucket
wipe. `rclone sync` also uses `--max-delete` (default 50, override with `MAX_DELETE` in compose).

**Quiet period:** have the work backup job `rm -f /mnt/backup/work/.backup-complete` at the start
and `touch /mnt/backup/work/.backup-complete` when it finishes. The push skips while that marker
is missing (backup running) or was touched within `QUIET_MINUTES` (default 30). A full-tree
`find` over large VM trees is intentionally not used.

For a one-off test before the marker workflow exists:

```bash
docker exec -e SKIP_QUIET=1 -e RCLONE_EXTRA=--dry-run s3sync /bin/sh /s3-push.sh
```

A dry run still walks the local tree and lists S3; on multi-TB backups it can take a long time
but should print `rclone sync /data -> s3:...` and periodic stats in `docker logs -f s3sync`.

## Bucket setup

1. Create the bucket and tie it to one IAM user:

   ```bash
   ./src/bin/s3-bucket.sh --region us-west-2 tec-backup arn:aws:iam::744686699669:user/NAME
   ```

2. Create an access key for that user and set `EST_BACKUP_ID` / `EST_BACKUP_KEY`.

3. As an account admin, enable versioning and lifecycle (not done by `s3-bucket.sh`):

   ```bash
   BUCKET=tec-backup-744686699669-us-west-2-an
   REGION=us-west-2

   aws s3api put-bucket-versioning --bucket "$BUCKET" --region "$REGION" \
     --versioning-configuration Status=Enabled

   aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --region "$REGION" \
     --lifecycle-configuration '{
       "Rules": [
         {
           "ID": "expire-old-versions",
           "Status": "Enabled",
           "Filter": {},
           "NoncurrentVersionExpiration": { "NoncurrentDays": 14 }
         },
         {
           "ID": "abort-incomplete-multipart",
           "Status": "Enabled",
           "Filter": {},
           "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 3 }
         }
       ]
     }'
   ```

**Cost notes:** `rclone sync` deletes remote objects removed locally. Versioning keeps recoverable
copies for a limited time; each old version of a large `.vdi` is a full object. The stack uses
`STANDARD_IA`, which has a 30-day minimum storage charge per upload—frequently changing VMs may
be cheaper on `STANDARD` or under a separate prefix with different flags.

## Deploy and run

```bash
./gradlew deployS3sync
# on the host, under /mnt/raid/services/s3sync:
docker compose up -d
```

Manual push:

```bash
docker exec s3sync /bin/sh /s3-push.sh
```

Dry run (use `SKIP_QUIET=1` if `.backup-complete` is not set up yet):

```bash
docker exec -e SKIP_QUIET=1 -e RCLONE_EXTRA=--dry-run s3sync /bin/sh /s3-push.sh
```

Progress during long runs: `docker logs -f s3sync` (stats every 5 minutes).

Test Gotify (silent on success; `gotify OK` means the message was accepted):

```bash
docker exec s3sync sh -c '. /gotify-notify.sh; gotify_notify 5 "s3sync test" "ping" && echo gotify OK || echo gotify FAIL'
```

The IAM policy from `s3-bucket.sh` allows only this bucket, so `rclone lsd s3:` from the
container will fail; use a dry run instead.

## Schedule

Crontab inside the container: `30 1 * * *` (01:30). Overlapping runs are skipped (file lock).
Runs are skipped when `.backup-complete` is missing or newer than `QUIET_MINUTES` (see above).
