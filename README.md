![Docker pulls](https://img.shields.io/docker/pulls/prodrigestivill/postgres-backup-local)
![GitHub actions](https://github.com/prodrigestivill/docker-postgres-backup-local/actions/workflows/ci.yml/badge.svg?branch=main)

# This clone

This repository extends the original by encrypting the backup on the fly with the public key of an X.509 certificate
or GnuPG key pair. 
The backups will be `bzip2` compressed and ssl-encrypted (`openssl smime -encrypt -aes256 -binary -outform DEM...`).
The backup will be encrypted against the public key in `${BACKUP_DIR}/${ENCRYPTION_CERT}`.
If no certificate file is found there, a new key/certificate is generated
with `${CERT_SUBJECT}` as its subject in this place (please move the private key to a safe place).

## X.509

**Warning:** Databases ecrypted with X.509 certificates suffer from an *openssh smime* issue that prevents decryption
of files larger than ~4GB because openssl is [refusing to implement stream support](https://github.com/openssl/openssl/issues/26372) 
which leaves may people with [perfectly encrypted files they cannot open any more
](https://mailing.openssl.users.narkive.com/rl6oJMF3/the-problem-of-decrypting-big-files-encrypted-with-openssl-smime)

To create an X.509 certificate, run
```shell
openssl req -x509 -nodes -days 1000000 \
    -newkey rsa:4096 \
    -subj "/C=NL/O=SmartSigns/OrganizationalUnit=DatabaseBackup/CN=sms_unified" \
    -keyout backup.key \
    -out backup.crt
```

To unpack the encrypted backup run the command below and paste the key (followed by a Control-D on an empty line).
(Should you have the key stored on file then replace `<(cat)` with the filename)
```bash
FILE=./backup/last/database-latest.dump.bz2.ssl
openssl smime -decrypt -in ${FILE} -binary -inform DEM -inkey <(cat) | \
    bzip2 --decompress > $(basename -s .bz2.ssl ${FILE})
```


The above can be piped directly into | pg_restore -d ${NEW_DB} (again: paste the key followed by Ctrl-D on an empty line or replace `<(cat)` with the filename)
```bash
openssl smime -decrypt -in ${FILE} -binary -inform DEM -inkey <(cat) | bzip2 --decompress --stdout \
    pg_restore -d ${NEW_DB}
```

## GnuPG

GnuPG keys have to be created and stored beforehand (there is no auto-generation of a key pair, yet). Store the `backup_databaseName.pub.asc`
with the correct database name in `${BACKUP_DIR}/certs/`

To create a GnuPG key pair, run

```shell
gpg2 --expert --full-gen-key
gpg --output backup_databaseName.pub.asc --armor --export KEY_NUMBER
gpg --output backup_databaseName.priv.asc --armor --export-secret-key KEY_NUMBER
```

To unpack the encrypted backup run the command below and paste the key (followed by a Control-D on an empty line).
```bash
FILE=./backup/last/database-latest.dump.bz2.ssl
./gpg_decrypt.sh ${FILE} decryptedDatabase.dump
```

# postgres-backup-local

Backup PostgresSQL to the local filesystem with periodic rotating backups, based on [schickling/postgres-backup-s3](https://hub.docker.com/r/schickling/postgres-backup-s3/).
Backup multiple databases from the same host by setting the database names in `POSTGRES_DB` separated by commas or spaces.

Supports the following Docker architectures: `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/s390x`, `linux/ppc64le`.

Please consider reading detailed the [How the backups folder works?](#how-the-backups-folder-works).

This application requires the docker volume `/backups` to be a POSIX-compliant filesystem to store the backups (mainly with support for hardlinks and softlinks). So filesystems like VFAT, EXFAT, SMB/CIFS, ... can't be used with this docker image.

## Usage

Docker:

```sh
docker run -u postgres:postgres -e POSTGRES_HOST=postgres -e POSTGRES_DB=dbname -e POSTGRES_USER=user -e POSTGRES_PASSWORD=password  \
  -v ./backups:/backups  prodrigestivill/postgres-backup-local
```

Docker Compose:

```yaml
services:
    postgres:
        image: postgres
        restart: always
        environment:
            - POSTGRES_DB=database
            - POSTGRES_USER=username
            - POSTGRES_PASSWORD=password
         #  - POSTGRES_PASSWORD_FILE=/run/secrets/db_password <-- alternative for POSTGRES_PASSWORD (to use with docker secrets)
    pgbackups:
        image: prodrigestivill/postgres-backup-local
        restart: always
        user: postgres:postgres # Optional: see below
        volumes:
            - /var/opt/pgbackups:/backups
        links:
            - postgres
        depends_on:
            - postgres
        environment:
            - POSTGRES_HOST=postgres
            - POSTGRES_DB=database
            - POSTGRES_USER=username
            - POSTGRES_PASSWORD=password
         #  - POSTGRES_PASSWORD_FILE=/run/secrets/db_password <-- alternative for POSTGRES_PASSWORD (to use with docker secrets)
            - POSTGRES_EXTRA_OPTS=-Z1 --schema=public --blobs
            - SCHEDULE=@daily
            - BACKUP_ON_START=TRUE
            - BACKUP_KEEP_DAYS=7
            - BACKUP_KEEP_WEEKS=4
            - BACKUP_KEEP_MONTHS=6
            - HEALTHCHECK_PORT=8080
            - ENCRYPTION_CERT=backup
            - CERT_SUBJECT=/C=NL/O=MyOrganization/OU=DatabaseBackup/CN=$${DB}
```

For security reasons it is recommended to run it as user `postgres:postgres`.

In case of running as `postgres` user, the system administrator must initialize the permission of the destination folder as follows:
```sh
# for default images (debian)
mkdir -p /var/opt/pgbackups && chown -R 999:999 /var/opt/pgbackups
# for alpine images
mkdir -p /var/opt/pgbackups && chown -R 70:70 /var/opt/pgbackups
```

### Environment Variables

Most variables are the same as in the [official postgres image](https://hub.docker.com/_/postgres/).

| env variable            | description                                                                                                                                                                                                                                                                     |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| BACKUP_DIR              | Directory to save the backup at. Defaults to `/backups`.                                                                                                                                                                                                                        |
| BACKUP_SUFFIX           | Filename suffix to save the backup. Defaults to `.sql.gz`.                                                                                                                                                                                                                      |
| BACKUP_ON_START         | If set to `TRUE` performs an backup on each container start or restart. Defaults to `FALSE`.                                                                                                                                                                                    |
| BACKUP_KEEP_DAYS        | Number of daily backups to keep before removal. Defaults to `7`.                                                                                                                                                                                                                |
| BACKUP_KEEP_WEEKS       | Number of weekly backups to keep before removal. Defaults to `4`.                                                                                                                                                                                                               |
| BACKUP_KEEP_MONTHS      | Number of monthly backups to keep before removal. Defaults to `6`.                                                                                                                                                                                                              |
| BACKUP_KEEP_MINS        | Number of minutes for `last` folder backups to keep before removal. Defaults to `1440`.                                                                                                                                                                                         |
| BACKUP_LATEST_TYPE      | Type of `latest` pointer (`symlink`,`hardlink`,`none`). Defaults to `symlink`.                                                                                                                                                                                                  |
| VALIDATE_ON_START       | If set to `FALSE` does not validate the configuration on start. Disabling this is not recommended. Defaults to `TRUE`.                                                                                                                                                          |
| HEALTHCHECK_PORT        | Port listening for cron-schedule health check. Defaults to `8080`.                                                                                                                                                                                                              |
| POSTGRES_DB             | Comma or space separated list of postgres databases to backup. If POSTGRES_CLUSTER is set this refers to the database to connect to for dumping global objects and discovering what other databases should be dumped (typically is either `postgres` or `template1`). Required. |
| POSTGRES_DB_FILE        | Alternative to POSTGRES_DB, but with one database per line, for usage with docker secrets.                                                                                                                                                                                      |
| POSTGRES_EXTRA_OPTS     | Additional [options](https://www.postgresql.org/docs/12/app-pgdump.html#PG-DUMP-OPTIONS) for `pg_dump` (or `pg_dumpall` [options](https://www.postgresql.org/docs/12/app-pg-dumpall.html#id-1.9.4.13.6) if POSTGRES_CLUSTER is set). Defaults to `"-Z zstd:9 -Fc"`.             |
| POSTGRES_CLUSTER        | Set to `TRUE` in order to use `pg_dumpall` instead. Also set POSTGRES_EXTRA_OPTS to any value or empty since the default value is not compatible with `pg_dumpall`.                                                                                                             |
| POSTGRES_HOST           | Postgres connection parameter; postgres host to connect to. Required.                                                                                                                                                                                                           |
| POSTGRES_PASSWORD       | Postgres connection parameter; postgres password to connect with. Required.                                                                                                                                                                                                     |
| POSTGRES_PASSWORD_FILE  | Alternative to POSTGRES_PASSWORD, for usage with docker secrets.                                                                                                                                                                                                                |
| POSTGRES_PASSFILE_STORE | Alternative to POSTGRES_PASSWORD in [passfile format](https://www.postgresql.org/docs/12/libpq-pgpass.html#LIBPQ-PGPASS), for usage with postgres clusters.                                                                                                                     |
| POSTGRES_PORT           | Postgres connection parameter; postgres port to connect to. Defaults to `5432`.                                                                                                                                                                                                 |
| POSTGRES_USER           | Postgres connection parameter; postgres user to connect with. Required.                                                                                                                                                                                                         |
| POSTGRES_USER_FILE      | Alternative to POSTGRES_USER, for usage with docker secrets.                                                                                                                                                                                                                    |
| SCHEDULE                | [Cron-schedule](http://godoc.org/github.com/robfig/cron#hdr-Predefined_schedules) specifying the interval between postgres backups. Defaults to `@daily`.                                                                                                                       |
| TZ                      | [POSIX TZ variable](https://www.gnu.org/software/libc/manual/html_node/TZ-Variable.html) specifying the timezone used to evaluate SCHEDULE cron (example "Europe/Paris").                                                                                                       |
| WEBHOOK_URL             | URL to be called after an error or after a successful backup (POST with a JSON payload, check `hooks/00-webhook` file for more info). Default disabled.                                                                                                                         |
| WEBHOOK_ERROR_URL       | URL to be called in case backup fails. Default disabled.                                                                                                                                                                                                                        |
| WEBHOOK_PRE_BACKUP_URL  | URL to be called when backup starts. Default disabled.                                                                                                                                                                                                                          |
| WEBHOOK_POST_BACKUP_URL | URL to be called when backup completes successfully. Default disabled.                                                                                                                                                                                                          |
| WEBHOOK_EXTRA_ARGS      | Extra arguments for the `curl` execution in the webhook (check `hooks/00-webhook` file for more info).                                                                                                                                                                          |
| ENCRYPTION_TYPE         | Which type of keys to use for encryption X.509 or gpg (default: X.509)                                                                                                                                                                                                          |
| ENCRYPTION_CERT         | Base name certificate/key files to use (default: backup_)                                                                                                                                                                                                                       |
| CERT_DIR                | Path to where the backup certificates are expected/created (Default: /backups/certs/)                                                                                                                                                                                           |
| CERT_SUBJECT            | Subject when no X.509 certificate is found for a database  (default: /C=NL/O=SmartSigns/OU=DatabaseBackup/CN=${DB})                                                                                                                                                             |

#### Special Environment Variables

These variables are not intended to be used for normal deployment operations:

| env variable | description |
|--|--|
| POSTGRES_PORT_5432_TCP_ADDR | Sets the POSTGRES_HOST when the latter is not set. |
| POSTGRES_PORT_5432_TCP_PORT | Sets POSTGRES_PORT when POSTGRES_HOST is not set. |

### How the backups folder works?

First a new backup is created in the `last` folder with the full time.

Once this backup finishes successfully, it is hard linked (instead of copying to avoid using more space) to the rest of the folders (daily, weekly and monthly). This step replaces the old backups for that category storing always only the latest for each category (so the monthly backup for a month is always storing the latest for that month and not the first).

So the backup folder are structured as follows:

* `BACKUP_DIR/last/DB-YYYYMMDD-HHmmss.sql.gz`: all the backups are stored separately in this folder.
* `BACKUP_DIR/daily/DB-YYYYMMDD.sql.gz`: always store (hard link) the **latest** backup of that day.
* `BACKUP_DIR/weekly/DB-YYYYww.sql.gz`: always store (hard link) the **latest** backup of that week (the last day of the week will be Sunday as it uses ISO week numbers).
* `BACKUP_DIR/monthly/DB-YYYYMM.sql.gz`: always store (hard link) the **latest** backup of that month (normally the ~31st).

And the following symlinks are also updated after each successful backup for simplicity:

```
BACKUP_DIR/last/DB-latest.sql.gz -> BACKUP_DIR/last/DB-YYYYMMDD-HHmmss.sql.gz
BACKUP_DIR/daily/DB-latest.sql.gz -> BACKUP_DIR/daily/DB-YYYYMMDD.sql.gz
BACKUP_DIR/weekly/DB-latest.sql.gz -> BACKUP_DIR/weekly/DB-YYYYww.sql.gz
BACKUP_DIR/monthly/DB-latest.sql.gz -> BACKUP_DIR/monthly/DB-YYYYMM.sql.gz
```

For **cleaning** the script removes the files for each category only if the new backup has been successful.
To do so it is using the following independent variables:

* BACKUP_KEEP_MINS: will remove files from the `last` folder that are older than its value in minutes after a new successful backup without affecting the rest of the backups (because they are hard links).
* BACKUP_KEEP_DAYS: will remove files from the `daily` folder that are older than its value in days after a new successful backup.
* BACKUP_KEEP_WEEKS: will remove files from the `weekly` folder that are older than its value in weeks after a new successful backup (remember that it starts counting from the end of each week not the beginning).
* BACKUP_KEEP_MONTHS: will remove files from the `monthly` folder that are older than its value in months (of 31 days) after a new successful backup (remember that it starts counting from the end of each month not the beginning).

### Hooks

The folder `hooks` inside the container can contain hooks/scripts to be run in differrent cases getting the exact situation as a first argument (`error`, `pre-backup` or `post-backup`).

Just create an script in that folder with execution permission so that [run-parts](https://manpages.debian.org/stable/debianutils/run-parts.8.en.html) can execute it on each state change.

Please, as an example take a look in the script already present there that implements the `WEBHOOK_URL` functionality.

### Manual Backups

By default this container makes daily backups, but you can start a manual backup by running `/backup.sh`.

This script as example creates one backup as the running user and saves it the working folder.

```sh
docker run --rm -v "$PWD:/backups" -u "$(id -u):$(id -g)" -e POSTGRES_HOST=postgres -e POSTGRES_DB=dbname -e POSTGRES_USER=user -e POSTGRES_PASSWORD=password  prodrigestivill/postgres-backup-local /backup.sh
```

### Automatic Periodic Backups

You can change the `SCHEDULE` environment variable in `-e SCHEDULE="@daily"` to alter the default frequency. Default is `daily`.

More information about the scheduling can be found [here](http://godoc.org/github.com/robfig/cron#hdr-Predefined_schedules).

Folders `daily`, `weekly` and `monthly` are created and populated using hard links to save disk space.

## Restore examples

Some examples to restore/apply the backups.

### Restore using the same container (not updated)

Not updated, yet, to decrypt; you might not want the key on the archiving file system anyhow.
So a nice solution would read the key from the terminal. 

To restore using the same backup container, replace `$BACKUPFILE`, `$CONTAINER`, `$USERNAME` and `$DBNAME` from the following command:

```sh
docker exec --tty --interactive $CONTAINER /bin/sh -c "zcat $BACKUPFILE | psql --username=$USERNAME --dbname=$DBNAME -W"
```

### Restore using a new container

Replace `$BACKUPFILE`, `$VERSION`, `$HOSTNAME`, `$PORT`, `$USERNAME` and `$DBNAME` from the following command:

```sh
docker run --rm --tty --interactive -v $BACKUPFILE:/tmp/backupfile.sql.gz postgres:$VERSION /bin/sh -c "zcat /tmp/backupfile.sql.gz | psql --host=$HOSTNAME --port=$PORT --username=$USERNAME --dbname=$DBNAME -W"
```

