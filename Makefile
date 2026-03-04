.PHONY: check_libheif_versions

ARCH ?= amd64

check_libheif_versions:
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.16.2 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.18.2 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.19.8 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.20.2 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.21.2 .

test:
	docker build --target=tested --platform=linux/$(ARCH) .
