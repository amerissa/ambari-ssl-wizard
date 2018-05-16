#!/bin/bash

if [ -z $1 ] && ! [ -s $1 ]; then
  echo Configs file does not exist, specify as first argument
  exit 1
fi

configs=$1

KEYLOC=`cat $config | grep KeyStoreLocation | cut -d "=" -f 2`
if [ -z $KEYLOC ]; then
  echo KeyStoreLocation is not specified
  exit 1
fi

TRUSTLOC=`cat $config | grep TrustStoreLocation | cut -d "=" -f 2`
if [ -z $TRUSTLOC ]; then
  echo TrustStoreLocation is not specified
  exit 1
fi

TRUSTPASS=`cat $config | grep TrustStorePassword | cut -d "=" -f 2`
if [ -z ${TRUSTPASS} ]; then
  echo TrustStorePassword is not specified
  exit 1
fi
cp $TRUSTLOC/truststore.jks $TRUSTLOC/truststore-ambari.jks

ambari-server setup-security --security-option=setup-https --truststore-type=jks --truststore-path=$TRUSTLOC/truststore-ambari.jks --truststore-password=${TRUSTPASS} --import-cert-path=$KEYLOC/server.pem --import-key-path=$KEYLOC/server.key --pem-password="" --api-ssl=true --api-ssl-port=8443

ambari-server setup-security --security-option=setup-truststore --truststore-type=jks --truststore-path=$TRUSTLOC/truststore-ambari.jks --truststore-password=${TRUSTPASS}
