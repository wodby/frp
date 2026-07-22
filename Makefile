-include env_make

FRP_VERSION ?= 0.69.1

REPO = wodby/frp
NAME = frp

TAG ?= $(FRP_VERSION)

PLATFORM ?= linux/arm64

IMAGETOOLS_TAG ?= $(TAG)

ifneq ($(ARCH),)
	override TAG := $(TAG)-$(ARCH)
endif

.PHONY: build buildx-build buildx-push buildx-imagetools-create test push shell run start stop logs clean release

default: build

build:
	docker build -t $(REPO):$(TAG) --build-arg FRP_VERSION=$(FRP_VERSION) ./

buildx-build:
	docker buildx build --platform $(PLATFORM) --build-arg FRP_VERSION=$(FRP_VERSION) -t $(REPO):$(TAG) \
		--load \
		./

buildx-push:
	docker buildx build --platform $(PLATFORM) --build-arg FRP_VERSION=$(FRP_VERSION) --push -t $(REPO):$(TAG) \
		./

buildx-imagetools-create:
	docker buildx imagetools create -t $(REPO):$(IMAGETOOLS_TAG) \
				$(REPO):$(TAG)-amd64 \
				$(REPO):$(TAG)-arm64
.PHONY: buildx-imagetools-create

test:
	echo 'no tests :('

push:
	docker push $(REPO):$(TAG)

shell:
	docker run --rm --name $(NAME) -i -t $(PORTS) $(VOLUMES) $(ENV) $(REPO):$(TAG) /bin/bash

run:
	docker run --rm --name $(NAME) $(PORTS) $(VOLUMES) $(ENV) $(REPO):$(TAG) $(CMD)

start:
	docker run -d --name $(NAME) $(PORTS) $(VOLUMES) $(ENV) $(REPO):$(TAG)

stop:
	docker stop $(NAME)

logs:
	docker logs $(NAME)

clean:
	-docker rm -f $(NAME)

release: build push
