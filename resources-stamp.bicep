@description('DNS label prefix: <prefix>.<region>.cloudapp.azure.com')
param subdomainName string

@description('Domain region: <prefix>.<region>.cloudapp.azure.com')
param location string

@description('Existing Public IP resource ID or \'newIp\' to indicate an IP address should be created.')
param ipResourceId string = 'newIp'

var normalizedSubdomain = replace(subdomainName, '.', '')
var storageAccountName = replace(replace(normalizedSubdomain, '_', ''), '-', '')
var appGatewayPublicIPAddressResourceId = ((ipResourceId == 'newIp') ? publicIPAddress.id : ipResourceId)

var subnetName = 'default'

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2020-11-01' = if (ipResourceId == 'newIp') {
  name: normalizedSubdomain
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: normalizedSubdomain
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {}
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: normalizedSubdomain
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '172.20.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '172.20.0.0/24'
        }
      }
    ]
  }

  resource subnet 'subnets' existing = {
    name: subnetName
  }
}

resource applicationGateway 'Microsoft.Network/applicationGateways@2020-11-01' = {
  name: normalizedSubdomain
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: virtualNetwork::subnet.id
          }
        }
      }
    ]
    sslCertificates: []
    trustedRootCertificates: []
    trustedClientCertificates: []
    sslProfiles: []
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: appGatewayPublicIPAddressResourceId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: normalizedSubdomain
        properties: {
          backendAddresses: [
            {
              fqdn: replace(replace(storageAccount.properties.primaryEndpoints.web, 'https://', ''), '/', '')
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: normalizedSubdomain
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', normalizedSubdomain, normalizedSubdomain)
          }
        }
      }
    ]
    httpListeners: [
      {
        name: normalizedSubdomain
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', normalizedSubdomain, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', normalizedSubdomain, 'port_80')
          }
          protocol: 'Http'
          hostNames: []
          requireServerNameIndication: false
        }
      }
    ]
    urlPathMaps: []
    requestRoutingRules: [
      {
        name: normalizedSubdomain
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', normalizedSubdomain, normalizedSubdomain)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', normalizedSubdomain, normalizedSubdomain)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', normalizedSubdomain, normalizedSubdomain)
          }
          rewriteRuleSet: {
            id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', normalizedSubdomain, normalizedSubdomain)
          }
        }
      }
    ]
    probes: [
      {
        name: normalizedSubdomain
        properties: {
          protocol: 'Https'
          path: '/ping'
          interval: 20
          timeout: 10
          unhealthyThreshold: 2
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {}
        }
      }
    ]
    rewriteRuleSets: [
      {
        name: normalizedSubdomain
        properties: {
          rewriteRules: [
            {
              ruleSequence: 100
              conditions: [
                {
                  variable: 'var_uri_path'
                  pattern: '^/.well-known/acme-challenge/(.+)$'
                  ignoreCase: true
                  negate: false
                }
              ]
              name: normalizedSubdomain
              actionSet: {
                requestHeaderConfigurations: []
                responseHeaderConfigurations: []
                urlConfiguration: {
                  modifiedPath: '/{var_uri_path_1}'
                  reroute: false
                }
              }
            }
          ]
        }
      }
    ]
    redirectConfigurations: []
    privateLinkConfigurations: []
    enableHttp2: false
  }
}

output storageAccountName string = storageAccountName
