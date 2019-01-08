# add values and then remove .tpl extension

export AZ_APP_ID=""
export AZ_CLIENT_SECRET=""
export AZ_TENANT_ID=""
export AZ_SUBSCRIPTION_ID=""

az login --service-principal -u "${AZ_APP_ID}" --password "${AZ_CLIENT_SECRET}" --tenant "${AZ_TENANT_ID}" > /dev/null
az account set -s "${AZ_SUBSCRIPTION_ID}" > /dev/null

az account show --output table 
