#!/bin/bash 
rg=devxherx10 #$1
vnetname=$(az network vnet list -g $rg --query "[].{Name:name}" -o tsv ) # $2
subnetName=Subnet1 #$3  #subnet 1 es back there are the funtions, subnet 2 is front
subnetback=Subnet1
echo Please wait we are getting the information of your Azure deployment

CosmosaccountName=$(az cosmosdb list -g $rg --query "[].{Name:name}" -o tsv)
mysqlServer=$(az mysql server list -g $rg --query "[].{Name:name}" -o tsv)
rule=camrule

echo Resource Group - $rg
echo vnetname - $vnetname
echo subnet - $subnetName
echo Costos Db - $CosmosaccountName
echo My sql  - $mysqlServer

read -p'Press any key if all configurations are ok '
az network public-ip create --resource-group $rg --name NatPublicIP --version IPv4 --sku Standard 

read -p'Public ip created, press any key to now configure the gatewat '
az network nat gateway create --resource-group $rg --name PwNATgateway --public-ip-addresses  NatPublicIP --idle-timeout 10

read -p'Gateway created, press any key to now add GW to vnet ' $vnetname ' subnet ' $subnetName
az network vnet subnet update --resource-group $rg --vnet-name $vnetname --name $subnetName --nat-gateway PwNATgateway

# https://docs.microsoft.com/en-us/azure/azure-functions/functions-how-to-use-nat-gateway#verify-current-outbound-ips this make functions to use the nat

svcEndpoint=$(az network vnet subnet show -g $rg -n $subnetback --vnet-name $vnetname --query 'id' -o tsv)
             #az network vnet subnet show -g devxherx6 -n Subnet1  --vnet-name VNet1 --query 'id' -o tsv
echo 'Nat Gateway configured'
echo $svcEndpoint

read -p'Press any key to now configure cosmosdb network rules ' #https://docs.microsoft.com/en-us/azure/cosmos-db/how-to-configure-firewall
echo Setting isVirtualNetworkFilterEnabled to true!!
az cosmosdb update --name $CosmosaccountName -g $rg --enable-virtual-network true 

echo adding network rule!!
az cosmosdb network-rule add -n $CosmosaccountName -g $rg --virtual-network $vnetname --subnet $svcEndpoint  --ignore-missing-vnet-service-endpoint true
#https://docs.microsoft.com/en-us/azure/cosmos-db/how-to-configure-vnet-service-endpoint here is how to block
#az cosmosdb network-rule add -n cosmos-devxherx6dev-io -g devxherx6 --virtual-network VNet1 --subnet Subnet1  --ignore-missing-vnet-service-endpoint true
#az cosmosdb show --name cosmos-devxherx6dev-io -g devxherx6 --query 'isVirtualNetworkFilterEnabled'
#az cosmosdb show --name cosmos-devxherx6dev-io -g devxherx6 --query 'isVirtualNetworkFilterEnabled'
#az cosmosdb update --name cosmos-devxherx6dev-io -g devxherx6 --enable-virtual-network true

echo finish adding network rule!!
read -p'Press any key to now configure the subnet for service endpoints for cosmos db'

az network vnet subnet update -n $subnetback -g $rg --vnet-name $vnetname --service-endpoints Microsoft.AzureCosmosDB Microsoft.ServiceBus
echo finish configuring the subnet for service endpoints for cosmos db!!
# read -p'Press any key to now to disable cosmosdb access from internet'
# az cosmosdb update --name $CosmosaccountName --resource-group $rg --enable-public-network false


read -p'Press any key to configure functions'
#https://docs.microsoft.com/en-us/azure/app-service/app-service-ip-restrictions
az functionapp list --resource-group $rg --query "[].{Name:name}" -o tsv |
while read -r name; do
    echo "Procesing function " $name 
    az functionapp config set --vnet-route-all-enabled false -g $rg -n $name 
    az functionapp config set -g $rg -n $name --ftps-state Disabled
    az functionapp update -g $rg -n $name --set httpsOnly=true
    az functionapp config access-restriction add --resource-group $rg --name $name --rule-name 'IP cam1' --action Allow --ip-address 3.9.236.119/32 --priority 100 
    az functionapp config access-restriction add --resource-group $rg --name $name --rule-name 'IP cam2' --action Allow --ip-address 18.130.49.85/32 --priority 100 
    az functionapp config access-restriction add --resource-group $rg --name $name --rule-name 'IP cam1' --action Allow --ip-address 18.205.167.41/32 --priority 100 
    az functionapp config access-restriction add --resource-group $rg --name $name --rule-name 'IP cam2' --action Allow --ip-address 34.198.68.230/32 --priority 100 
    az functionapp config set --vnet-route-all-enabled true -g $rg -n $name 
done



# mysql changes 
# enforce ssl https://docs.microsoft.com/en-us/azure/mysql/howto-configure-ssl
# echo internet access to cosmosdb disabled!!
read -p'Press any key to enforce ssl on Mysql'
az mysql server update --resource-group $rg --name $mysqlServer --ssl-enforcement Enabled

echo finish enforcing ssl!
read -p'Press any key to configure vnet on Mysql'

#mysql end point https://docs.microsoft.com/en-us/azure/mysql/howto-manage-vnet-using-cli
#https://docs.microsoft.com/en-us/azure/mysql/concepts-data-access-and-security-vnet
#Configure Vnet service endpoints for Azure Database for MySQL

az network vnet subnet update --name $subnetback --resource-group $rg --vnet-name $vnetname --service-endpoints Microsoft.SQL Microsoft.AzureCosmosDB Microsoft.ServiceBus
az mysql server vnet-rule create --name $rule --resource-group $rg --server $mysqlServer --vnet-name $vnetname --subnet $subnetback
#https://docs.microsoft.com/en-us/azure/mysql/concepts-data-access-security-private-link#deny-public-access-for-azure-database-for-mysql

echo finish configuring vnet for mysql!
read -p'Press any key to disable public ip access to Mysql'
az mysql server update --resource-group $rg --name $mysqlServer  --set publicNetworkAccess="Disabled"


echo finish public ip mysql is disable
