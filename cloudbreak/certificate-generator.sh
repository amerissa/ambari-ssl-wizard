#!/bin/bash

function generatekeys {
  keytool -genkey -noprompt -alias gateway-identity -keyalg RSA -dname "CN=$host, OU=$OU, O=$O, L=$L, S=$S, C=$C" -keystore $shost.jks -storepass "$KEYPASS"  -keypass "$KEYPASS"
}

function generatecsr {
  keytool -certreq -noprompt -alias gateway-identity -keyalg RSA -keystore $shost.jks -storepass "$KEYPASS"  -keypass "$KEYPASS" > $shost.csr
}

function importcert {
  for cert in `ls ca/`; do
    keytool -importcert -noprompt -file ca/$cert -alias $cert  -keystore $shost.jks -storepass "$KEYPASS"
  done
  keytool -importcert -noprompt -alias gateway-identity -file $shost.cer -keystore $shost.jks -storepass "$KEYPASS"
}

function signcsrs {
  openssl x509 -req -in $shost.csr -CA $domain.cer -CAkey $domain.key -CAcreateserial -out $shost.cer -days 1024 -sha256
}

function generateca {
  openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
      -subj "/C=$C/ST=$S/L=$L/O=$O/CN=$domain" \
      -keyout $domain.key  -out $domain.cer
  mkdir -p ca/
  cp $domain.cer ca/
}

function generatetruststore {
  for cert in `ls ca/`; do
    keytool -importcert -noprompt -file ca/$cert -alias $cert -keystore truststore.jks -storepass "$TRUSTPASS"
  done
}

function updatecacerts {
  cp /etc/alternatives/java_sdk/jre/lib/security/cacerts ./
  for cert in `ls ca/`; do
    keytool -importcert -noprompt -file ca/$cert -alias $cert -keystore cacerts -storepass changeit
  done
}

function generatepems {
  keytool -importkeystore -srckeystore $shost.jks \
    -srcstorepass "$KEYPASS" -srckeypass "$KEYPASS" -destkeystore $shost.p12 \
    -deststoretype PKCS12 -srcalias gateway-identity -deststorepass "$KEYPASS" -destkeypass "$KEYPASS"
  openssl pkcs12 -in $shost.p12 -passin pass:$KEYPASS  -nokeys -out $shost.pem
  openssl pkcs12 -in $shost.p12 -passin pass:$KEYPASS -passout pass:$KEYPASS -nocerts -out $shost.keytemp
  openssl rsa -in $shost.keytemp -passin pass:$KEYPASS -out $shost.key
  rm -f $shost.p12 $shost.keytemp
  rm -f $shost.keytemp
}

function pushkeys {
  mkdir -p $KEYLOC
  mkdir -p $TRUSTLOC
  rsync -arP /root/ambari-ssl-wizard/atlas.creds /etc/pki/creds.jceks
  rsync -arP /root/ambari-ssl-wizard/$shost.jks ${KEYLOC}/server.jks
  rsync -arP /root/ambari-ssl-wizard/truststore.jks ${TRUSTLOC}/truststore.jks
  rsync -arP /root/ambari-ssl-wizard/$shost.cer ${KEYLOC}/server.pem
  rsync -arP /root/ambari-ssl-wizard/$shost.key ${KEYLOC}/server.key
  rsync -arP /root/ambari-ssl-wizard/ranger.jks ${KEYLOC}/ranger-plugin.jks
  rsync -arP /root/ambari-ssl-wizard/cacerts /etc/alternatives/java_sdk/jre/lib/security/cacerts
  chmod ugo+rx $TRUSTLOC -R
  chmod ugo+rx $KEYLOC -R
}

if [ -z $1 ]; then
  echo -e "Usage: $0 [CHOICE] [CONFIGFile] {LocalAuthority|GenerateCA|GenerateTruststore|GenerateRanger}\n LocalAuthority: Generate Local Server Keys and Pems.\n GenerateCA: Generate CA, run once and run first.\n GenerateTruststore: Run after placing CA certs in ca folder, run after generate CA.\n GenerateRanger: Generate Ranger Plugins keystore"
  exit 1
fi

config=$2

if [ -z $config ] && ! [ -s $config ]; then
  echo Configs file does not exist, specify as first argument
  exit 1
fi

OU=`cat $config | grep OrgUnit | cut -d "=" -f 2`
if [ -z $OU ]; then
  echo OrgUnit is not specified
  exit 1
fi

O=`cat $config | grep Organization | cut -d "=" -f 2`
if [ -z "$O" ]; then
  echo Organization is not specified
  exit 1
fi

L=`cat $config | grep City | cut -d "=" -f 2 `
if [ -z $L ]; then
  echo City is not specified
  exit 1
fi

S=`cat $config | grep State | cut -d "=" -f 2`
if [ -z $S ]; then
  echo State is not specified
  exit 1
fi

C=`cat $config | grep CountryCode | cut -d "=" -f 2`
if [ -z $C ]; then
  echo CountryCode is not specified
  exit 1
fi

KEYPASS=`cat $config | grep KeyStorePassword | cut -d "=" -f 2`
if [ -z $KEYPASS ]; then
  echo KeyStorePassword is not specified
  exit 1
fi

TRUSTPASS=`cat $config | grep TrustStorePassword | cut -d "=" -f 2`
if [ -z $TRUSTPASS ]; then
  echo TrustStorePassword is not specified
  exit 1
fi

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

domain=`cat $config | grep Domain | cut -d "=" -f 2`
if [ -z $domain ]; then
  echo Domain is not specified
  exit 1
fi


mkdir -p ca

case $1 in
  LocalAuthority)
    host=$(hostname -f)
    shost=`echo $host | cut -d . -f 1`
    generatekeys
    generatecsr
    signcsrs
    importcert
    generatepems
    updatecacerts
    pushkeys
    ;;
  GenerateCA)
    generateca
    ;;
  GenerateTruststore)
    generatetruststore
    ;;
  GenerateRanger)
    host=ranger.$domain
    shost=`echo $host | cut -d . -f 1`
    generatekeys
    generatecsr
    signcsrs
    importcert
    generatepems
    ;;

  *)
    echo -e "Usage: $0 [CHOICE] [CONFIGFile] {LocalAuthority|GenerateCA|GenerateTruststore|GenerateRanger}\n LocalAuthority: Generate Local Server Keys and Pems.\n GenerateCA: Generate CA, run once and run first.\n GenerateTruststore: Run after placing CA certs in ca folder, run after generate CA.\n GenerateRanger: Generate Ranger Plugins keystore"
    ;;
esac
