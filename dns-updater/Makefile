IMG ?= ljfranklin/dynamic-dns
IMG_TAG ?= latest

# Build the docker image
docker-build:
	IMAGE=$(IMG) ./docker/build.sh

# Push the docker image
docker-push:
	docker push $(IMG):amd64-$(IMG_TAG)
	docker push $(IMG):arm32v6-$(IMG_TAG)
	docker push $(IMG):arm64v8-$(IMG_TAG)
	docker manifest create --amend $(IMG):$(IMG_TAG) $(IMG):amd64-$(IMG_TAG) $(IMG):arm32v6-$(IMG_TAG) $(IMG):arm64v8-$(IMG_TAG)
	docker manifest annotate $(IMG):$(IMG_TAG) $(IMG):arm32v6-$(IMG_TAG) --os linux --arch arm
	docker manifest annotate $(IMG):$(IMG_TAG) $(IMG):arm64v8-$(IMG_TAG) --os linux --arch arm64 --variant armv8
	docker manifest push --purge $(IMG):$(IMG_TAG)
