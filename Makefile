.PHONY: check_libheif_versions

ARCH ?= amd64

check_libheif_versions:
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.16.2 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.17.0 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.17.5 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.17.6 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.18.0 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.18.1 .
	docker build --target=libheif --platform=linux/$(ARCH) --build-arg=LIBHEIF_VERSION=1.18.2 .

test:
	docker build --target=tested --platform=linux/$(ARCH) .
