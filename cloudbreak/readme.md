# For Cloudbreak Deployments:
This repo can be used to Cloudbreak autoamtion. Follow the steps below:

### Steps:
1. Edit the config file and add the certificate info and domain
2. Run the certificate-generator.sh with the option GenerateCA
3. Replace the certificate-generator.sh to the one in this folder
4. Put the company’s CA certs in the ca folder (probably AD one and anything else they want)
5. Run the certificate-generator.sh with the option GenerateTruststore
6. Run the certificate-generator.sh with the option GenerateRanger
7. Copy the folder to the cloudbreak server
8. Edit the preinstall recipe change the ssh key portion to the one that can ssh back to the cloudbreak server
9. Edit the preinstall and change the ip to the cloudbreak server

### Cloudbreak Recipes:
* preinstall.sh runs on every node as a pre-ambari-start
* postinstall.sh runs only on the Ambari server node as a post-cluster-install
