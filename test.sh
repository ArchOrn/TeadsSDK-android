#!/bin/sh
set -xe

docker_name_friendly () { echo $1 | sed -e 's/[^a-zA-Z0-9_.-]/_/g' | awk '{print tolower($0)}'; }

IMAGE=$(echo ${JOB_NAME:-$(basename `pwd`)} | cut -d/ -f1 | sed "s/[^-]*-//" | sed "s/\_.*//")
IMAGE=$(docker_name_friendly $IMAGE)
BRANCH=${gitlabSourceBranch:-${GIT_BRANCH#remotes/}}
BRANCH=${BRANCH#origin/}
BRANCH=$(docker_name_friendly ${BRANCH:-$(git symbolic-ref --short HEAD)})
HASH=${GIT_COMMIT:-$(git rev-parse HEAD)}
TAG=$(docker_name_friendly ${BUILD_TAG:-$$})

# unify GNU/BSD xargs behavior
xargs -h 2>&1 | grep -q gnu && alias xargs='xargs -r'
hash timeout 2>/dev/null || { [ "$(uname)" = "Darwin" ] && hash gtimeout 2>/dev/null && alias timeout="gtimeout"; } || { echo "gtimeout not found: install coreutils via brew"; exit 1; }

# ephemeral containers should be prefixed with $TAG so that they are automatically dumped and destroyed
containers () { docker ps -a | awk '{print $NF}' | grep "^$TAG[a-zA-Z0-9_.-]*$"; }
dump_containers () { rm -rf ./containers && mkdir ./containers && containers | xargs -L1 sh -c 'docker logs $1 > ./containers/$1.log 2>./containers/$1.err' -- ; }
destroy_containers () { containers | xargs docker kill | xargs docker rm -f -v; }
cleanup () { trap '' INT; dump_containers; destroy_containers; }
trap cleanup EXIT TERM
trap true INT

DOCKER_REGISTRY='docker-registry.teads.net'

# common changes above this line should be done upstream #
##########################################################

# Make sure caches are accessible from the host
mkdir -p ~/.gradle && chmod g+s ~/.gradle

# Test and publish image locally
chmod g+s .
docker run --rm -i \
	-v ~/.gradle:/root/.gradle \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v `pwd`:/opt/workspace:rw -w /opt/workspace \
	-e "KEY_FILE=${JENKINS_HOME}/${ANDROID_KEY_FILE}" \
	-e "STORE_PASSWORD=${ANDROID_KEY_PASSWORD}" \
	-e "KEY_ALIAS=${ANDROID_KEY_ALIAS}" \
	-e "KEY_PASSWORD=${ANDROID_KEY_PASSWORD}" \
      ${DOCKER_REGISTRY}/android:24.3.4 \
      sh -c "cd TeadsSDKDemo && ./gradlew clean assembleRelease \
      -Pandroid.injected.signing.store.file=${KEY_FILE} \
      -Pandroid.injected.signing.store.password=${STORE_PASSWORD} \
      -Pandroid.injected.signing.key.alias=${KEY_ALIAS} \
      -Pandroid.injected.signing.key.password=${KEY_PASSWORD}"
