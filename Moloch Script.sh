#!/bin/sh

#  Moloch Script.sh
#  
#
#  Created by John Farese on 8/8/14.
#
TDIR="/data/moloch"
if [ "$#" -gt "0" ]; then
TDIR="$1"
echo "Installing to ${TDIR}"
fi


ES=1.1.2
NODEJS=0.10.28
INSTALL_DIR=$PWD

if [ "$(id -u)" != "0" ]; then
echo "ERROR - This script must be run as root" 1>&2
exit 1
fi

pver=`python -c 'import sys; print("%i" % (sys.hexversion>=0x02060000))'`
if [ $pver -eq 0 ]; then
echo "ERROR - node.js requires python 2.6 or higher to build"
exit 1
fi

if [ "$(umask)" != "022" -a "$(umask)" != "0022" ]; then
echo "WARNING - Using a umask of 022 is STRONGLY recommended - $(umask) - script will try setting to 022 before proceeding" 1>&2
sleep 3
fi

umask 022

if [ "$(stat --printf=%a easybutton-singlehost.sh)" != "755" ]; then
echo "WARNING - looks like a umask 022 wasn't used for git clone, this might cause strange errors" 1>&2
sleep 3
fi

if [ -d "${TDIR}/logs" ]; then
echo "WARNING - looks like moloch was already installed on this host, make sure elasticsearch and capture aren't running" 1>&2
echo "You probably don't want to use this script.  See https://github.com/aol/moloch#upgrading" 1>&2
sleep 5
fi


echo -n "Looking for java "
which java
JAVA_VAL=$?

if [ $JAVA_VAL -ne 0 ]; then
echo -n "java command not found, real Java 7 is recommended for large install, however would you like to install openjdk 7 now? [yes] "
read INSTALLJAVA
if [ -n "$INSTALLJAVA" -a "x$INSTALLJAVA" != "xyes" ]; then
echo "Install java and try again"
exit
fi

if [ -f "/etc/debian_version" ]; then
apt-get install openjdk-7-jdk
if [ $? -ne 0 ]; then
echo "ERROR - 'apt-get install openjdk-7-jdk' failed"
exit
fi
elif [ -f "/etc/redhat-release" ]; then
yum install java-1.7.0-openjdk
if [ $? -ne 0 ]; then
echo "ERROR - 'yum install java-1.7.0-openjdk' failed"
exit
fi
else
echo "ERROR - Not sure how to install java for this OS, please install and run again"
exit
fi
fi

if [ "x$http_proxy" != "x" ]; then
JAVA_OPTS="$JAVA_OPTS `echo $http_proxy | sed 's/https*:..\(.*\):\(.*\)/-Dhttp.proxyHost=\1 -Dhttp.proxyPort=\2/'`"
export JAVA_OPTS
echo "Because http_proxy is set ($http_proxy) setting JAVA_OPTS to ($JAVA_OPTS)"
sleep 1
fi

if [ "x$https_proxy" != "x" ]; then
JAVA_OPTS="$JAVA_OPTS `echo $https_proxy | sed 's/https*:..\(.*\):\(.*\)/-Dhttps.proxyHost=\1 -Dhttps.proxyPort=\2/'`"
export JAVA_OPTS
echo "Because https_proxy is set ($https_proxy) setting JAVA_OPTS to ($JAVA_OPTS)"
sleep 1
fi

echo -n "Use pfring? ('yes' enables) [no] "
read USEPFRING
PFRING=""
if [ -n "$USEPFRING" -a "x$USEPFRING" = "xyes" ]; then
echo "MOLOCH - Using pfring - Make sure to install the kernel modules"
sleep 1
PFRING="--pfring"
fi

# Building thirdparty libraries and moloch
echo ./easybutton-build.sh --dir "$TDIR" $PFRING
./easybutton-build.sh --dir "$TDIR" $PFRING
if [ $? -ne 0 ]; then
exit 1
fi

# Increase limits
grep -q "hard.*nofile.*128000" /etc/security/limits.conf
LIMIT_VAL=$?
if [ $LIMIT_VAL -ne 0 ]; then
echo "MOLOCH: Adding entries to /etc/security/limits.conf"
echo "* hard nofile 128000" >> /etc/security/limits.conf
echo "* soft nofile 128000" >> /etc/security/limits.conf
echo "root hard nofile 128000" >> /etc/security/limits.conf
echo "root soft nofile 128000" >> /etc/security/limits.conf
fi


# Install area
echo "MOLOCH: Creating install area"
mkdir -p ${TDIR}/data
mkdir -p ${TDIR}/logs
mkdir -p ${TDIR}/raw
mkdir -p ${TDIR}/etc
mkdir -p ${TDIR}/bin
mkdir -p ${TDIR}/db



# ElasticSearch
echo "MOLOCH: Downloading and installing elastic search"
cd ${INSTALL_DIR}/thirdparty
if [ ! -f "elasticsearch-${ES}.tar.gz" ]; then
wget http://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-${ES}.tar.gz
fi

cd ${TDIR}
tar xfz ${INSTALL_DIR}/thirdparty/elasticsearch-${ES}.tar.gz
cd elasticsearch-${ES}
./bin/plugin -install mobz/elasticsearch-head
./bin/plugin -install lukas-vlcek/bigdesk


# NodeJS
echo "MOLOCH: Downloading and installing node"
cd ${INSTALL_DIR}/thirdparty
if [ ! -f "node-v${NODEJS}.tar.gz" ]; then
wget http://nodejs.org/dist/v${NODEJS}/node-v${NODEJS}.tar.gz
fi

tar xfz node-v${NODEJS}.tar.gz
cd node-v${NODEJS}
./configure
make
make install
./configure --prefix=${TDIR}
make install

if [ "x$http_proxy" != "x" ]; then
${TDIR}/bin/npm config set proxy $http_proxy
echo "Because http_proxy is set ($http_proxy) setting npm proxy"
sleep 1
fi

if [ "x$https_proxy" != "x" ]; then
${TDIR}/bin/npm config set https-proxy $https_proxy
echo "Because https_proxy is set ($https_proxy) setting npm https-proxy"
sleep 1
fi

cd ${TDIR}/etc/
if [ ! -f "GeoIP.dat" ]; then
wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz
gunzip GeoIP.dat.gz
fi

if [ ! -f "GeoIPASNum.dat" ]; then
wget http://www.maxmind.com/download/geoip/database/asnum/GeoIPASNum.dat.gz
gunzip GeoIPASNum.dat.gz
fi

if [ ! -f "ipv4-address-space.csv" ]; then
wget https://www.iana.org/assignments/ipv4-address-space/ipv4-address-space.csv
fi

echo "MOLOCH: Installing"
cd ${INSTALL_DIR}
PATH=${TDIR}/bin:${PATH}
make install

if [ $? -ne 0 ]; then
echo "ERROR - 'make install' in moloch directory failed"
exit 1
fi



echo -n "Memory to give to elasticsearch, box MUST have more then this available: [512M] "
read ESMEM
if [ -z $ESMEM ]; then ESMEM="512M"; fi

echo "MOLOCH: Copying single-host config files"
cp ${INSTALL_DIR}/single-host/etc/* ${TDIR}/etc
cat ${INSTALL_DIR}/single-host/etc/elasticsearch.yml | sed -e "s,_TDIR_,${TDIR},g" > ${TDIR}/etc/elasticsearch.yml

cat ${INSTALL_DIR}/single-host/bin/run_es.sh | sed -e "s,_TDIR_,${TDIR},g" -e "s/_ES_/${ES}/g" -e "s/_ESMEM_/${ESMEM}/g" > ${TDIR}/bin/run_es.sh
cat ${INSTALL_DIR}/single-host/bin/run_capture.sh | sed -e "s,_TDIR_,${TDIR},g" > ${TDIR}/bin/run_capture.sh
cat ${INSTALL_DIR}/single-host/bin/run_viewer.sh | sed -e "s,_TDIR_,${TDIR},g" > ${TDIR}/bin/run_viewer.sh
chmod 755 ${TDIR}/bin/run*.sh


cat ${INSTALL_DIR}/db/daily.sh | sed -e "s,CHANGEMEHOST:CHANGEMEPORT,localhost:9200,g" > ${TDIR}/db/daily.sh


chown daemon:daemon ${TDIR}/viewer/public
chown daemon:daemon ${TDIR}/raw

echo "MOLOCH: Running config script"


${INSTALL_DIR}/easybutton-config.sh "$TDIR"


echo "MOLOCH: Starting ElasticSearch"

${TDIR}/bin/run_es.sh

sleep 10

echo "MOLOCH: Building database"
cd ${TDIR}/db
./db.pl localhost:9200 init


echo "MOLOCH: Adding user admin/admin"
cd ${TDIR}/viewer
../bin/node addUser.js -c ../etc/config.ini admin "Admin" admin -admin

echo "MOLOCH: Starting viewer and capture"
cd ${TDIR}/bin
nohup ./run_viewer.sh &
nohup ./run_capture.sh &


HOSTNAME=`hostname`
echo "MOLOCH: Complete use https://$HOSTNAME:8005 to access.  You should also make the run_* scripts in ${TDIR}/bin run on start up and look at the config files in ${TDIR}/etc"
