# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SHELL                    := /bin/bash
COMMIT                   ?= $(shell git rev-parse HEAD)
LABEL                    ?= org.airshipit.build=community
IMAGE_NAME               ?= image-builder
DOCKER_REGISTRY          ?= quay.io
IMAGE_PREFIX             ?= airshipit
IMAGE_TAG                ?=
IMAGE_TAG_FIRST          ?=
IMAGE_TYPE               ?= iso # iso | qcow
PUSH_IMAGE               ?= false
DISTRO                   ?= ubuntu_focal
WORKDIR                  ?= ./manifests
# Specifiy if you want to use a different profile than the default.
#	i.e. PROFILE ?= k8s-1.18
PROFILE                  ?=
QCOW_BUNDLE              ?= ${WORKDIR}/qcow-bundle
# Specify if you want to only build a certain subset of QCOW bundles
QCOW_BUNDLE_DIRS         ?=
# Set to true to skip multistrap.sh script. Useful for testing
SKIP_MULTISTRAP          ?=
# Set to true to skip multistrap playbook. Useful for testing
SKIP_MULTI_ROLE          ?=
# Set to true to skip osconfig playbook. Useful for testing
SKIP_OSCONFIG_ROLE       ?=
# Set to true to skip livecdcontent playbook. Useful for testing
SKIP_LIVECDCONTENT_ROLE  ?=
IMAGE                    ?= ${DOCKER_REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}-${DISTRO}
TARGET_IMAGE_TAG         ?=
PROXY                    ?=
NO_PROXY                 ?= localhost,127.0.0.1
# Image boot validation timeout. Set to 0 to disable to make console available for manual debugging.
BOOT_TIMEOUT             ?= 300
#it doesn't matter - we're not going to publish it, because it's useless without jsons
KRM_IMAGE_TAG            ?= latest
KRM_BASE_IMAGE           ?= ${DOCKER_REGISTRY}/${IMAGE_PREFIX}/image-profile-krm:${KRM_IMAGE_TAG}

.PHONY: help build images cut_image package_qcow krm_base_image run clean docker_build tag push

.ONESHELL:

help: ## This help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

# Make target name that zuul expects for each project in this repo
images: build generate_iso package_qcow clean

build:
	set -ex
ifneq ($(PROFILE), )
	# Apply any user-defined profiles overrides to playbooks
	rsync -rc ./../profiles/$(PROFILE)/manifests/ $(WORKDIR)/
endif
	# Apply any user-defined rootfs overrides to playbooks
	cp $(WORKDIR)/rootfs/multistrap-vars.yaml assets/playbooks/roles/multistrap/vars/main.yaml
	cp $(WORKDIR)/rootfs/osconfig-vars.yaml assets/playbooks/roles/osconfig/vars/main.yaml
	cp $(WORKDIR)/rootfs/livecdcontent-vars.yaml assets/playbooks/roles/livecdcontent/vars/main.yaml

	export DOCKERFILE=Dockerfile.$(DISTRO)
	export DOCKERFILE_FOLDER="."
	export IMAGE_NAME=image-builder
	export SOURCE_IMAGE_TAG=${DOCKER_REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}-${DISTRO}
ifneq (,$(findstring latest, $(IMAGE_TAG)))
ifneq ($(PROXY), )
	sudo -E ./tools/docker_proxy.sh $(PROXY) $(NO_PROXY)
	export http_proxy=$(PROXY)
	export https_proxy=$(PROXY)
	export no_proxy=$(NO_PROXY)
	export HTTP_PROXY=$(PROXY)
	export HTTPS_PROXY=$(PROXY)
	export NO_PROXY=$(NO_PROXY)
ifneq ($(SKIP_MULTISTRAP), true)
	sudo -E ./tools/multistrap.sh $(WORKDIR)
endif
# run docker build for w/proxy
	sudo -E make docker_build
else
ifneq ($(SKIP_MULTISTRAP), true)
	sudo -E ./tools/multistrap.sh $(WORKDIR)
endif
# run docker build for wo/proxy
	sudo -E make docker_build
endif
	imgId=`sudo docker images | grep 'image-builder ' | awk '{print $$3}'`
	time sudo -E DOCKER_BUILDKIT=1 docker run $$imgId ls -ltra /build/usr/bin/sudo > /tmp/sticky_result
	time sudo grep '^-rws' /tmp/sticky_result >& /dev/null || \
		(echo Could not find sticky bit set on target image sudo binary. Are you using buildkit? && \
		sudo cat /tmp/sticky_result && exit 1)
else
# Set SOURCE_IMAGE_TAG and TARGET_IMAGE_TAG for tagging purposes
	export SOURCE_IMAGE_TAG="${DOCKER_REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG_FIRST}-${DISTRO}"
	export TARGET_IMAGE_TAG="${DOCKER_REGISTRY}/${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}-${DISTRO}"
	# Don't repackage image-builder, just tag it.
	sudo -E make tag
endif
ifeq ($(PUSH_IMAGE), true)
	sudo -E make push
endif

cut_image: krm_base_image
	set -ex
	IMAGE_NAME=image-builder
ifneq ($(PROXY), )
	sudo -E ./tools/docker_proxy.sh $(PROXY) $(NO_PROXY)
	export http_proxy=$(PROXY)
	export https_proxy=$(PROXY)
	export no_proxy=$(NO_PROXY)
	export HTTP_PROXY=$(PROXY)
	export HTTPS_PROXY=$(PROXY)
	export NO_PROXY=$(NO_PROXY)
endif
ifeq ($(IMAGE_TYPE), iso)
	sudo -E tools/cut_image.sh $(IMAGE_TYPE) $(WORKDIR)/iso $(IMAGE) $(BOOT_TIMEOUT) "$(PROXY)" "$(NO_PROXY)"
else
	# Assemble all images based on configs defined in each subdirectory
	#                     Trailing / allows proper function with symlinks
	iterDirs="$$(find $(QCOW_BUNDLE)/ -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)"
	if [[ -z $$iterDirs ]]; then
		echo "Could not find any qcow images defined for bundle - exiting."
		exit 1
	fi
	for subdir in $$iterDirs; do
		# QCOW configs
		export osconfig_params="$(QCOW_BUNDLE)/$$subdir/osconfig-vars.yaml"
		export qcow_params="$(QCOW_BUNDLE)/$$subdir/qcow-vars.yaml"
		# Image name
		export img_name=$$subdir.qcow2
		echo "Image: $(IMAGE)"
		echo "SOURCE_IMAGE_TAG: $(SOURCE_IMAGE_TAG)"
		sudo -E tools/cut_image.sh $(IMAGE_TYPE) $(QCOW_BUNDLE) $(IMAGE) $(BOOT_TIMEOUT) "$(PROXY)" "$(NO_PROXY)"
	    # keep profile info
	    [ -e $(QCOW_BUNDLE)/profile_entrypoint.json ] && cat $(QCOW_BUNDLE)/profile_entrypoint.json && mv $(QCOW_BUNDLE)/profile_entrypoint.json $(QCOW_BUNDLE)/profile_qcow_$$subdir.json
	done
endif

generate_iso:
	set -ex
	export IMAGE_TYPE=iso
	export IMAGE_NAME=image-builder
	sudo -E make cut_image

package_qcow:
	set -ex
	export IMAGE_TYPE=qcow
ifneq ($(QCOW_BUNDLE_DIRS), )
	bundleDirs="$(QCOW_BUNDLE_DIRS)"
else
	# Assemble all images based on configs defined in each $(IMAGE_TYPE)* subdirectory
	#                   Trailing / allows proper function with symlinks
	bundleDirs="$$(find $(WORKDIR)/ -maxdepth 1 -mindepth 1 -name "qcow-bundle*" -type d -exec basename {} \;)"
endif
	if [[ -z $$bundleDirs ]]; then
	    echo "Could not find any qcow bundle directories - exiting."
	    exit 1
	fi
	for bundledir in $$bundleDirs; do
# if IMAGE_TAG contains latest then docker_build else its a tag
ifneq (,$(findstring latest, $(IMAGE_TAG)))
# Set vars for docker_build and push
		export QCOW_BUNDLE="$(WORKDIR)/$$bundledir"
		export IMAGE_NAME=image-builder
		sudo -E make cut_image
		export DOCKERFILE="Dockerfile-qcow.$(DISTRO)"
		export DOCKERFILE_FOLDER="$(WORKDIR)/$$bundledir"
		export IMAGE_NAME=$$bundledir
		export SOURCE_IMAGE_TAG=${DOCKER_REGISTRY}/${IMAGE_PREFIX}/$$bundledir:${IMAGE_TAG}-${DISTRO}
		sudo -E make docker_build
else
# Set SOURCE_IMAGE_TAG & TARGET_IMAGE_TAG for tagging purposes
		export SOURCE_IMAGE_TAG=${DOCKER_REGISTRY}/${IMAGE_PREFIX}/$$bundledir:${IMAGE_TAG_FIRST}-${DISTRO}
		export TARGET_IMAGE_TAG="${DOCKER_REGISTRY}/${IMAGE_PREFIX}/$$bundledir:${IMAGE_TAG}-${DISTRO}"
		# Don't repackage qcow, just tag it.
		sudo -E make tag
endif
ifeq ($(PUSH_IMAGE), true)
		sudo -E make push
endif
	done

krm_base_image:
	sudo -E docker build krm-function -t $(KRM_BASE_IMAGE)

docker_build:
	set -ex
ifneq ($(PROXY), )
	sudo -E DOCKER_BUILDKIT=1 docker -D -l debug build --tag $(SOURCE_IMAGE_TAG) -f $(DOCKERFILE) $(DOCKERFILE_FOLDER) \
	--label $(LABEL) \
	--label "org.opencontainers.image.revision=$(COMMIT)" \
	--label "org.opencontainers.image.created=$(shell date --rfc-3339=seconds --utc)" \
	--label "org.opencontainers.image.title=$(IMAGE_NAME)" \
	--build-arg http_proxy=$(PROXY) \
	--build-arg https_proxy=$(PROXY) \
	--build-arg HTTP_PROXY=$(PROXY) \
	--build-arg HTTPS_PROXY=$(PROXY) \
	--build-arg no_proxy=$(NO_PROXY) \
	--build-arg NO_PROXY=$(NO_PROXY) \
	--build-arg KRM_BASE_IMAGE=$(KRM_BASE_IMAGE)
else
	sudo -E DOCKER_BUILDKIT=1 docker -D -l debug build --tag $(SOURCE_IMAGE_TAG) -f $(DOCKERFILE) $(DOCKERFILE_FOLDER) \
	--label $(LABEL) \
	--label "org.opencontainers.image.revision=$(COMMIT)" \
	--label "org.opencontainers.image.created=$(shell date --rfc-3339=seconds --utc)" \
	--label "org.opencontainers.image.title=$(IMAGE_NAME)"
endif

tag:
	set -ex
	sudo -E DOCKER_BUILDKIT=1 docker tag $(SOURCE_IMAGE_TAG) $(TARGET_IMAGE_TAG)

push:
	set -ex
	sudo -E DOCKER_BUILDKIT=1 docker image push --all-tags $(SOURCE_IMAGE_TAG)

tests:
	true

clean:
	set -ex
	sudo -E tools/multistrap.sh clean
	find $(WORKDIR) -name "*.iso" -exec rm -f {} \; >& /dev/null
	find $(WORKDIR) -name "*.qcow2" -exec rm -f {} \; >& /dev/null
	find $(WORKDIR) -name "*.snapshot" -exec rm -f {} \; >& /dev/null
	find $(WORKDIR) -name "*.md5sum" -exec rm -f {} \; >& /dev/null
