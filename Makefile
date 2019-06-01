bla = $(shell pwd)
build:
	docker build -t docker-postgres-backup .

buildrestic:
	docker run --rm -v "$(bla):/data" golang /bin/bash -c "git clone https://github.com/restic/restic && cd restic && go run build.go && cp restic /data/restic_app"

push:
	docker tag docker-postgres-backup jmcarbo/docker-postgres-backup:11.3
	docker push jmcarbo/docker-postgres-backup:11.3

