#!/bin/bash

if [ "${POSTGRES_ENV_POSTGRES_PASSWORD}" == "**Random**" ]; then
        unset POSTGRES_ENV_POSTGRES_PASSWORD
fi

RESTIC_PASSWORD=${RESTIC_PASSWORD:-$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c16)}
POSTGRES_HOST=${POSTGRES_PORT_5432_TCP_ADDR:-${POSTGRES_HOST}}
POSTGRES_HOST=${POSTGRES_PORT_1_5432_TCP_ADDR:-${POSTGRES_HOST}}
POSTGRES_PORT=${POSTGRES_PORT_5432_TCP_PORT:-${POSTGRES_PORT}}
POSTGRES_PORT=${POSTGRES_PORT_1_3306_TCP_PORT:-${POSTGRES_PORT}}
POSTGRES_USER=${POSTGRES_USER:-${POSTGRES_ENV_POSTGRES_USER}}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-${POSTGRES_ENV_POSTGRES_PASSWORD}}

[ -z "${POSTGRES_HOST}" ] && { echo "=> POSTGRES_HOST cannot be empty" && exit 1; }
[ -z "${POSTGRES_PORT}" ] && { echo "=> POSTGRES_PORT cannot be empty" && exit 1; }
[ -z "${POSTGRES_USER}" ] && { echo "=> POSTGRES_USER cannot be empty" && exit 1; }
[ -z "${POSTGRES_PASSWORD}" ] && { echo "=> POSTGRES_PASSWORD cannot be empty" && exit 1; }
[ -z "${POSTGRES_DB}" ] && { echo "=> POSTGRES_DB cannot be empty" && exit 1; }

export PGPASSWORD="${POSTGRES_PASSWORD}"

BACKUP_CMD="pg_dump -h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U ${POSTGRES_USER} -f /backup/\${BACKUP_NAME} ${EXTRA_OPTS} ${POSTGRES_DB}"

echo ${MINIO_HOST}
if [ -n "${MINIO_HOST}" ]; then
	[ -z "${MINIO_HOST_URL}" ] && { echo "=> MINIO_HOST_URL cannot be empty" && exit 1; }
	[ -z "${MINIO_ACCESS_KEY}" ] && { echo "=> MINIO_ACCESS_KEY cannot be empty" && exit 1; }
	[ -z "${MINIO_SECRET_KEY}" ] && { echo "=> MINIO_SECRET_KEY cannot be empty" && exit 1; }
	[ -z "${MINIO_BUCKET}" ] && { echo "=> MINIO_BUCKET cannot be empty" && exit 1; }

	while ! curl -s ${MINIO_HOST_URL}
	do
		echo "waiting for minio container..."
		sleep 1
	done

	mkdir -p "$HOME/.mc"
cat <<EOF >"$HOME/.mc/config.json"
{
	"version": "8",
	"hosts": {
	"${MINIO_HOST}": {
	"url": "${MINIO_HOST_URL}",
	"accessKey": "${MINIO_ACCESS_KEY}",
	"secretKey": "${MINIO_SECRET_KEY}",
	"api": "S3v4"
	}
	}
}
EOF
	echo $RESTIC_PASSWORD

        mc ls "${MINIO_HOST}/${MINIO_BUCKET}"
        if [[ $? -eq 1 ]];
	then 
	        mc mb "${MINIO_HOST}/${MINIO_BUCKET}" 
		echo "Bucket ${MINIO_BUCKET} created" 
		echo "$RESTIC_PASSWORD"	| mc pipe "${MINIO_HOST}/${MINIO_BUCKET}/restic_password.txt"
		mc mb "${MINIO_HOST}/${MINIO_BUCKET}restic"
		export AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY}
		export AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}
		export RESTIC_PASSWORD
		restic -r "s3:${MINIO_HOST_URL}/${MINIO_BUCKET}restic" init
	else 
		echo "Bucket ${MINIO_BUCKET} already exists" 
		RESTIC_PASSWORD=$(mc cat "${MINIO_HOST}/${MINIO_BUCKET}/restic_password.txt")
	fi

	echo $RESTIC_PASSWORD
	BACKUP_RESTIC_CMD="/usr/local/bin/restic backup /backup && /usr/local/bin/restic forget ${RESTIC_FORGET} && /usr/local/bin/restic prune"
	export RESTIC_PASSWORD=$(mc cat "${MINIO_HOST}/${MINIO_BUCKET}/restic_password.txt")

cat <<EOF >>/root/.bashrc
export AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}
export RESTIC_PASSWORD=$(mc cat "${MINIO_HOST}/${MINIO_BUCKET}/restic_password.txt")
export RESTIC_REPOSITORY=s3:${MINIO_HOST_URL}/${MINIO_BUCKET}restic
EOF

fi


echo "=> Creating backup script"
rm -f /backup.sh
cat <<EOF >> /backup.sh
#!/bin/bash
MAX_BACKUPS=${MAX_BACKUPS}

BACKUP_NAME=\$(date +\%Y.\%m.\%d.\%H\%M\%S).sql

export PGPASSWORD="${POSTGRES_PASSWORD}"

export MINIO_HOST=${MINIO_HOST}
if [ -n "\${MINIO_HOST}" ]; then
	export AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY}
	export AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}
	export RESTIC_PASSWORD=${RESTIC_PASSWORD}
	export RESTIC_REPOSITORY=s3:${MINIO_HOST_URL}/${MINIO_BUCKET}restic
fi

echo "=> Backup started: \${BACKUP_NAME}"
if ${BACKUP_CMD} ;then
    echo "   Backup succeeded"
    ${BACKUP_RESTIC_CMD}
else
    echo "   Backup failed"
    rm -rf /backup/\${BACKUP_NAME}
fi

if [ -n "\${MAX_BACKUPS}" ]; then
    while [ \$(ls /backup -N1 | wc -l) -gt \${MAX_BACKUPS} ];
    do
        BACKUP_TO_BE_DELETED=\$(ls /backup -N1 | sort | head -n 1)
        echo "   Backup \${BACKUP_TO_BE_DELETED} is deleted"
        rm -rf /backup/\${BACKUP_TO_BE_DELETED}
    done
fi
echo "=> Backup done"
EOF
chmod +x /backup.sh

echo "=> Creating restore script"
rm -f /restore.sh
cat <<EOF >> /restore.sh
#!/bin/bash
export PGPASSWORD="${POSTGRES_PASSWORD}"

export MINIO_HOST=${MINIO_HOST}
if [ -n "\${MINIO_HOST}" ]; then
	export AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY}
	export AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}
	export RESTIC_PASSWORD=${RESTIC_PASSWORD}
	export RESTIC_REPOSITORY=s3:${MINIO_HOST_URL}/${MINIO_BUCKET}restic
fi
echo "=> Restore database from \$1"
if psql -h${POSTGRES_HOST} -p${POSTGRES_PORT} -U${POSTGRES_USER} < \$1 ;then
    echo "   Restore succeeded"
else
    echo "   Restore failed"
fi
echo "=> Done"
EOF
chmod +x /restore.sh

touch /postgres_backup.log
tail -F /postgres_backup.log &

if [ -n "${INIT_BACKUP}" ]; then
    echo "=> Create a backup on the startup"
    /backup.sh
elif [ -n "${INIT_RESTORE_LATEST}" ]; then
    echo "=> Restore latest backup"
    until nc -z $POSTGRES_HOST $POSTGRES_PORT
    do
        echo "waiting database container..."
        sleep 1
    done
    ls -d -1 /backup/* | tail -1 | xargs /restore.sh
elif [ -n "${INIT_RESTORE_URL}" ]; then
	MINIO_HOST=${MINIO_HOST:-myminio}
	[ -z "${MINIO_HOST_URL}" ] && { echo "=> MINIO_HOST_URL cannot be empty" && exit 1; }
	[ -z "${MINIO_ACCESS_KEY}" ] && { echo "=> MINIO_ACCESS_KEY cannot be empty" && exit 1; }
	[ -z "${MINIO_SECRET_KEY}" ] && { echo "=> MINIO_SECRET_KEY cannot be empty" && exit 1; }

	mkdir -p "$HOME/.mc"
cat <<EOF >"$HOME/.mc/config.json"
{
	"version": "7",
	"hosts": {
	"${MINIO_HOST}": {
	"url": "${MINIO_HOST_URL}",
	"accessKey": "${MINIO_ACCESS_KEY}",
	"secretKey": "${MINIO_SECRET_KEY}",
	"api": "S3v4"
	}
	}
}
EOF
	mc cp "${INIT_RESTORE_URL}" /backup/restore_target.sql 	
    	until nc -z $POSTGRES_HOST $POSTGRES_PORT
    	do
        	echo "waiting database container..."
        	sleep 1
    	done
	/restore.sh /backup/restore_target.sql
fi

echo "${CRON_TIME} /backup.sh >> /postgres_backup.log 2>&1" > /crontab.conf
crontab  /crontab.conf
echo "=> Running cron job"
exec cron -f
