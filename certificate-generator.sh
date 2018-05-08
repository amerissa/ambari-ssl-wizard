#!/bin/bash

function generatekeys {
  for host in $hosts; do
    echo $host
    shost=`echo $host | cut -d . -f 1`
    $java_home/bin/keytool -genkey -noprompt -alias gateway-identity -keyalg RSA -dname "CN=$host, OU=$OU, O=$O, L=$L, S=$S, C=$C" -keystore $shost.jks -storepass "$KEYPASS"  -keypass "$KEYPASS"
  done
}

function generatecsr {
  for host in $hosts; do
    echo $host
    shost=`echo $host | cut -d . -f 1`
    $java_home/bin/keytool -certreq -noprompt -alias gateway-identity -keyalg RSA -keystore $shost.jks -storepass "$KEYPASS"  -keypass "$KEYPASS" > $shost.csr
  done
}

function importcert {
  for host in $hosts; do
    shost=`echo $host |cut -d . -f 1`
    for cert in `ls ca/`; do
      $java_home/bin/keytool -importcert -noprompt -file ca/$cert -alias $cert  -keystore $shost.jks -storepass "$KEYPASS"
    done
    $java_home/bin/keytool -importcert -noprompt -alias gateway-identity -file $shost.cer -keystore $shost.jks -storepass "$KEYPASS"
  done

}

function signcsrs {
  for host in $hosts; do
    echo $host
    shost=`echo $host |cut -d . -f 1`
    openssl x509 -req -in $shost.csr -CA $domain.cer -CAkey $domain.key -CAcreateserial -out $shost.cer -days 1024 -sha256
  done
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
    $java_home/bin/keytool -importcert -noprompt -file ca/$cert -alias $cert -keystore truststore.jks -storepass "$TRUSTPASS"
  done
}

function updatecacerts {
  cp $java_home/jre/lib/security/cacerts ./
  cp /etc/pki/tls/certs/ca-bundle.crt ./
  for cert in `ls ca/`; do
    $java_home/bin/keytool -importcert -noprompt -file ca/$cert -alias $cert -keystore cacerts -storepass changeit
    cat ca/$cert >> ca-bundle.crt
  done
}

function generatepems {
  for host in $hosts; do
    echo $host
    shost=`echo $host | cut -d . -f 1`
    $java_home/bin/keytool -importkeystore -srckeystore $shost.jks \
      -srcstorepass "$KEYPASS" -srckeypass "$KEYPASS" -destkeystore $shost.p12 \
      -deststoretype PKCS12 -srcalias gateway-identity -deststorepass "$KEYPASS" -destkeypass "$KEYPASS"
    openssl pkcs12 -in $shost.p12 -passin pass:$KEYPASS  -nokeys -out $shost.pem
    openssl pkcs12 -in $shost.p12 -passin pass:$KEYPASS -passout pass:$KEYPASS -nocerts -out $shost.keytemp
    openssl rsa -in $shost.keytemp -passin pass:$KEYPASS -out $shost.key
    rm -f $shost.p12 $shost.keytemp
    rm -f $shost.keytemp
  done
}

function atlas {
  hadoop credential keystore.password -provider jceks://file$(pwd)/creds.jceks -value "$KEYPASS"
  hadoop credential password -provider jceks://file$(pwd)/creds.jceks -value "$KEYPASS"
  hadoop credential truststore.password -provider jceks://file$(pwd)/creds.jceks -value "$TRUSTPASS"
}

function pushkeys {
  for host in $hosts; do
    if [ $host != "ranger.$domain" ]; then
      shost=`echo $host | cut -d . -f 1`
      ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $host sudo mkdir -p $KEYLOC\; sudo chmod ugo+rx $KEYLOC
      ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $host sudo mkdir -p $TRUSTLOC\; sudo chmod ugo+rx $TRUSTLOC
      rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP creds.jceks $host:/tmp/
      ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $host sudo cp /tmp/creds.jceks /etc/pki/creds.jceks
      rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP $shost.jks $host:${KEYLOC}/server.jks
      rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP truststore.jks $host:${TRUSTLOC}/truststore.jks
      rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP $shost.cer $host:${KEYLOC}/server.pem
      rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP $shost.key $host:${KEYLOC}/server.key
      rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP ranger.jks $host:${KEYLOC}/ranger-plugin.jks
      rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP cacerts $host:/tmp/
      ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $host sudo cp /tmp/cacerts $java_home/jre/lib/security/cacerts
      rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP ca-bundle.crt $host:/tmp/ca-bundle.crt
      ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $host sudo cp /tmp/ca-bundle.crt /etc/pki/tls/certs/ca-bundle.crt
    fi
  done
}

if [ -z $1 ]; then
  echo -e "Usage: $0 [CHOICE] [CONFIGFile] {LocalAuthority|LocalAuthority|RemoteAuthorityImportCertsAndPush}\n LocalAuthority: Generate local CA, generate truststore and keystores, and push to servers.\n RemoteAuthorityGenerateCSR: Generate keystore and CSR's to be signed be a remote authority.\n RemoteAuthorityImportCertsAndPush: Import certs generated by remote authority. Naming should shorthostame.cer. RemoteAuthorityGenerateCSR must be run first and CSR's from that signed"
  exit 1
fi

config=$2

if [ -z $config ] && ! [ -s $config ]; then
  echo Configs file does not exist, specify as first argument
  exit 1
fi

hostsfile=`cat $config | grep HostFile | cut -d "=" -f 2`
if [ -z "$hostsfile" ] && ! [ -s "$hostsfile" ]; then
  echo Host file is not specified or empty
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
if [ -z "$L" ]; then
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
if [ -z ${KEYPASS} ]; then
  echo KeyStorePassword is not specified
  exit 1
fi

TRUSTPASS=`cat $config | grep TrustStorePassword | cut -d "=" -f 2`
if [ -z ${TRUSTPASS} ]; then
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

echo ranger.$domain >> $hostsfile
hosts=`cat $hostsfile`

mkdir -p ca

export java_home=`grep "java.home=" /etc/ambari-server/conf/ambari.properties | cut -d = -f 2 |head -1`

case $1 in
  LocalAuthority)
    generateca
    generatekeys
    generatecsr
    signcsrs
    generatetruststore
    importcert
    generatepems
    atlas
    updatecacerts
    pushkeys
    ;;
  RemoteAuthorityGenerateCSR)
    generatekeys
    generatecsr
    ;;
  RemoteAuthorityImportCertsAndPush)
    importcert
    generatetruststore
    generatepems
    atlas
    updatecacerts
    pushkeys
    ;;
  *)
    echo -e "Usage: $0 [CHOICE] [CONFIGFile] {LocalAuthority|LocalAuthority|RemoteAuthorityImportCertsAndPush}\n LocalAuthority: Generate local CA, generate truststore and keystores, and push to servers.\n RemoteAuthorityGenerateCSR: Generate keystore and CSR's to be signed be a remote authority.\n RemoteAuthorityImportCertsAndPush: Import certs generated by remote authority. Naming should shorthostame.cer. RemoteAuthorityGenerateCSR must be run first and CSR's from that signed"
    ;;
esac
