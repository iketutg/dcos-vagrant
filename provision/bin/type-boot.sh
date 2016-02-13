#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

echo ">>> Starting zookeeper (for exhibitor bootstrap and quorum)"
docker run -d -p 2181:2181 -p 2888:2888 -p 3888:3888 jplock/zookeeper

echo ">>> Starting nginx (for distributing bootstrap artifacts to cluster)"
docker run -d -v /var/tmp/dcos:/usr/share/nginx/html -p 80:80 nginx

mkdir -p ~/dcos/genconf

echo ">>> Installing ip-detect (for detecting the current node IP)"
cat > ~/dcos/genconf/ip-detect << EOF
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

echo \$(/usr/sbin/ip route show to match ${DCOS_MASTER_IPS%% *} | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | tail -1)

EOF

echo ">>> Configuring DCOS bootstrap"
# support json or yaml config files
curl "${DCOS_CONFIG_PATH}" > ~/dcos/genconf/config.${DCOS_CONFIG_PATH##*.}

echo ">>> Downloading dcos_generate_config.sh (for building bootstrap image for system)"
curl "${DCOS_GENERATE_CONFIG_PATH}" > ~/dcos/dcos_generate_config.sh

cd ~/dcos
echo ">>> Building bootstrap artifacts ($(pwd)/genconf/serve)"
bash ./dcos_generate_config.sh

# Provide a local docker registry for testing purposes. Agents will also get
# the boot node allowed as an insecure registry.
if [ "${DCOS_PRIVATE_REGISTRY}" == "true" ]; then
  echo ">>> Starting private docker registry"
  docker run -d -p 5000:5000 --restart=always registry:2
fi

# TODO: sleeping seems to be necessary for DCOS 1.5... bug?
SLEPT=0
while [ ! -d ~/dcos/genconf/serve ] && [ ${SLEPT} -lt 10 ]; do
  sleep 1
  let SLEPT=SLEPT+1
done

echo ">>> Copying bootstrap artifacts to nginx directory (/var/tmp/dcos)."
cp -rpv ~/dcos/genconf/serve/* /var/tmp/dcos/

if [ "${DCOS_JAVA_ENABLED:-false}" == "true" ]; then
  echo ">>> Copying java artifacts to nginx directory (/var/tmp/dcos/java)."
  mkdir -p /var/tmp/dcos/java
  cp -rp /vagrant/provision/gs-spring-boot-0.1.0.jar /var/tmp/dcos/java/
  cp -rp /vagrant/provision/jre-*-linux-x64.* /var/tmp/dcos/java/
fi