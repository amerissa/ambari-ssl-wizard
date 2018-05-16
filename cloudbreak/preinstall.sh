#!/bin/bash
cbserver="CLOUDBREAKSERVER"
tee ~/.ssh/id_rsa << EOF
{KEY}
EOF
chmod 600 ~/.ssh/id_rsa
pip-2.7 install requests --upgrade
cd ~/
rsync -e 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' -arP cloudbreak@$cbserver:~/ambari-ssl-wizard ./
cd ambari-ssl-wizard
hostname -f  > hosts
./certificate-generator.sh LocalAuthority configs

if yum list installed | grep ambari-server; then
  cp /etc/security/pki/truststore.jks /etc/security/pki/truststore-ambari.jks
  ambari-server setup -s -j /etc/alternatives/java_sdk
  ambari-server setup-security --security-option=setup-truststore --truststore-reconfigure --truststore-type=jks --truststore-path=/etc/security/pki/truststore-ambari.jks --truststore-password=`cat configs | grep TrustStorePassword | cut -d "=" -f 2`
fi
