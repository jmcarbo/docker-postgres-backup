build:
	docker build -t docker-postgres-backup .

buildrestic:
	git clone https://github.com/restic/restic.git || true
	docker run --rm -v "$$PWD/restic":/usr/src/restic -w /usr/src/restic golang go run build.go
	cp restic/restic restic_app
