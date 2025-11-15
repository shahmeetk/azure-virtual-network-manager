targetScope = 'resourceGroup'

param location string
param vnetName string
param ipamPoolId string = ''
param numberOfIpAddresses string = ''
param environment string
param includeTagValue string = 'spokes'
param includeTagName string = 'avnm-group'
param descriptionTag string = ''
param createdDateTag string = ''
param resourceTags object = {}
param virtualNetworkAddressPrefixes array = []

var requiredTags = {
  Environment: environment
}
var tags = union(requiredTags, resourceTags)

var useIpam = !empty(ipamPoolId) && !empty(numberOfIpAddresses)
var virtualNetworkDnsServers = ['172.16.6.132']

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: useIpam ? {
    addressSpace: json('{"ipamPoolPrefixAllocations":[{"pool":{"id":"${ipamPoolId}"},"numberOfIpAddresses":"${numberOfIpAddresses}"}]}')
    dhcpOptions: {
      dnsServers: virtualNetworkDnsServers
    }
    subnets: []
  } : {
    addressSpace: {
      addressPrefixes: virtualNetworkAddressPrefixes
    }
    dhcpOptions: {
      dnsServers: virtualNetworkDnsServers
    }
  }
  tags: union(tags, { '${includeTagName}': includeTagValue })
}

output vnetId string = vnet.id