IP_RESOURCE_ID=$1

LOCATION=$(az network public-ip show --ids $IP_RESOURCE_ID --query location -o tsv)
RGNAME="rg-lets-encrypt-cert-validator-${LOCATION}"

FQDN=$(az network public-ip show --ids $IP_RESOURCE_ID --query dnsSettings.fqdn -o tsv)
SUBDOMAIN=$(az network public-ip show --ids $IP_RESOURCE_ID --query dnsSettings.domainNameLabel -o tsv)

echo "Location: $LOCATION"
echo "DNS Prefix: $SUBDOMAIN"
echo "FQDN: $FQDN"
echo "Existing IP Resource ID: $IP_RESOURCE_ID"

echo "Creating temporary Resource Group $RGNAME"
az group create -n $RGNAME -l $LOCATION

echo "Deploying Azure resources used in validation; this may take 20 minutes."
az deployment group create -g $RGNAME -f resources-stamp.json -n $SUBDOMAIN -p location=${LOCATION} subdomainName=${SUBDOMAIN} ipResourceId=${IP_RESOURCE_ID}

STORAGE_ACCOUNT_NAME=$(az deployment group show -g $RGNAME -n $SUBDOMAIN --query properties.outputs.storageAccountName.value -o tsv)

echo "Enabling web hosting on $STORAGE_ACCOUNT_NAME"
az storage blob service-properties update --account-name $STORAGE_ACCOUNT_NAME --static-website true --auth-mode login

echo "Uploading placeholder to storage"
echo pong>ping.txt
az storage blob upload --account-name $STORAGE_ACCOUNT_NAME -c \$web -n ping -f ./ping.txt --auth-mode key

echo "Starting cert generation and validation"
sudo certbot certonly --manual --manual-auth-hook "./authenticator.sh ${STORAGE_ACCOUNT_NAME}" -d $FQDN

echo "Converting cert to pfx"
sudo cp /etc/letsencrypt/live/${FQDN}/privkey.pem .
sudo cp /etc/letsencrypt/live/${FQDN}/cert.pem .
sudo cp /etc/letsencrypt/live/${FQDN}/chain.pem .
openssl pkcs12 -export -out ${SUBDOMAIN}.pfx -inkey privkey.pem -in cert.pem -certfile chain.pem -passout pass:

echo "Deleting Azure resources"
az group delete -n $RGNAME --yes

echo "Deleting temporary local files"
rm ping.txt
rm privkey.pem
rm cert.pem
rm chain.pem

echo "Your certificate: ${SUBDOMAIN}.pfx"