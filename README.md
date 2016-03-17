# docker-postgres-backup

This image runs pg_dump to backup data using cronjob to folder `/backup`

## Usage:

    docker run -d \
        --env PG_HOST=mysql.host \
        --env PG_PORT=27017 \
        --env PG_USER=admin \
        --env PG_PASSWORD=password \
        --volume host.folder:/backup
        jmcarbo/docker-postgres-backup

Moreover, if you link `jmcarbo/docker-postgres-backup` to a postgres container (e.g. `tutum/mysql`) with an alias named pg, this image will try to auto load the `host`, `port`, `user`, `pass` if possible.

    docker run -d -p 27017:27017 -p 28017:28017 -e PG_PASS="mypass" --name pg postgres
    docker run -d --link pg:pg -v host.folder:/backup jmcarbo/docker-postgres-backup

## Parameters

    POSTGRES_HOST      the host/ip of your postgres database
    POSTGRES_PORT      the port number of your postgres database
    POSTGRES_USER      the username of your postgres database
    POSTGRES_PASSWORD      the password of your postgres database
    POSTGRES_DB        the database name to dump. Default: `--all-databases`
    EXTRA_OPTS      the extra options to pass to pg_dump command
    CRON_TIME       the interval of cron job to run pg_dump. `0 0 * * *` by default, which is every day at 00:00
    MAX_BACKUPS     the number of backups to keep. When reaching the limit, the old backup will be discarded. No limit by default
    INIT_BACKUP     if set, create a backup when the container starts
    INIT_RESTORE_LATEST if set, restores latest backup

    INIT_RESTORE_URL restore from minio url ex: myminio/bla/file.sql 
    MINIO_HOST name of minio host ex: myminio
    MINIO_HOST_URL ex: https://myminio.my.io
    MINIO_ACCESS_KEY minio access key
    MINIO_SECRET_KEY minio secret key

## Restore from a backup

See the list of backups, you can run:

    docker exec docker-postgres-backup ls /backup

To restore database from a certain backup, simply run:

    docker exec docker-postgres-backup /restore.sh /backup/2015.08.06.171901
