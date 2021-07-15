#####################################
# Input Parameters                  #
#####################################
$date = Get-Date -Format "yyMMdd-HHmmss"
$logPath = "E:\Prometheus-powershell-Export\logs"
$location = "yourLocation"
Start-Transcript -Path $logPath\${date}-Get-AzureStack-$location-Admin.ps1.log -Force
$ArmEndpoint   = 'https://adminmanagement.$location.contoso.com'
$client_id     = 'your client id'
$client_secret = 'your client secret'
$AADTenantName = "yourAADTenant.onmicrosoft.com"
  
$EnvironmentName = "AzureStackAdmin$location"
$jobname = "azs-admin-metrics"
$stamp = $location
$adminSubscription = "your admin subscription id"
 
#####################################
# Clean old logfiles                #
#####################################
$logFile = "*-Get-AzureStack-$location-Admin.ps1.log"
$timeLimit = (Get-Date).AddDays(-7) 
if(Test-Path "$logPath\$logFile"){Get-ChildItem "$logPath\$logFile" -File | where { $_.LastWriteTime -lt $timeLimit } | Remove-Item -Force}
 
 
############################################################
# Set variables to get the endpoint Information needed     #
# Get Tenant Id and create access token                    #
############################################################
   
$Environment = Add-AzureRmEnvironment -Name $EnvironmentName -ARMEndpoint $ArmEndpoint
$ActiveDirectoryServiceEndpointResourceId = $Environment.ActiveDirectoryServiceEndpointResourceId.TrimEnd('/')
$AuthEndpoint = (Get-AzureRmEnvironment -Name $EnvironmentName).ActiveDirectoryAuthority.TrimEnd('/')
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]
$AccessTokenUri = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").token_endpoint
 
#####################################
# Request Bearer Token              #
#####################################
  
# Request Bearer Token
$body = "grant_type=client_credentials&amp;client_id=$client_id&amp;client_secret=$client_secret&amp;resource=$ActiveDirectoryServiceEndpointResourceId"
$Token = Invoke-RestMethod -Method Post -Uri $AccessTokenUri -Body $body -ContentType 'application/x-www-form-urlencoded'
  
# Create Rest API Headers
$Headers = @{}
$Headers.Add("Authorization","$($Token.token_type)" + " " + "$($Token.access_token)")
$Headers.Add("Accept","application/json")
$Headers.Add("x-ms-effective-locale","en.en-us")
 
# Create Rest API Headers
$Headers = @{}
$Headers.Add("Authorization","$($Token.token_type)" + " " + "$($Token.access_token)")
$Headers.Add("Accept","application/json")
$Headers.Add("x-ms-effective-locale","en.en-us")
 
#region List Region Health through API
$ListRegionHealth = "$ArmEndPoint/subscriptions/$adminSubscription/resourcegroups/system.local/providers/Microsoft.InfrastructureInsights.Admin/regionHealths?api-version=2016-05-01"
$RegionHealth = (Invoke-RestMethod -Uri $ListRegionHealth -ContentType "application/json" -Headers $Headers -Method Get -Debug -Verbose).value
 
$results = $null
foreach($x in $RegionHealth)
    {
    foreach($metric in $x)
        {
        foreach($m in $metric.properties.usageMetrics)
            {
 
            $name = $m.name.Replace(" ","_").ToLower()
            $location = $x.location
 
            $result1 = "#HELP {0}`n" -f $name
            $result2 = "#TYPE {0} gauge`n" -f $name
            $results += $result1
            $results += $result2
             
            foreach($mValue in $m.metricsValue)
                {
                $valueName = $mValue.name
                $unit = $mValue.unit
                $value = $mValue.value
 
                $result3 = "azs_{0}{{location=`"{1}`",valueName=`"{2}`",unit=`"{3}`"}} {4}`n" -f @($name, $location, $valueName, $unit, $value)
                $results += $result3
 
                }
 
            }
        }
    }
 
$responseRegionHealth = Invoke-WebRequest -Uri "http://localhost:9091/metrics/job/$jobname/instance/$stamp" -Method Post -Body $results
#endregion
 
#region List configured Quotas through API
$ListConfiguredQuotas = "$ArmEndPoint/subscriptions/$adminSubscription/providers/Microsoft.Compute.Admin/locations/$stamp/quotas?api-version=2015-12-01-preview"
$ConfiguredQuotas = (Invoke-RestMethod -Uri $ListConfiguredQuotas -ContentType "application/json" -Headers $Headers -Method Get -Debug -Verbose).value
 
$results = $null
$name = $null
$name = "quotas"
 
$result1 = "#HELP {0}`n" -f $name
$result2 = "#TYPE {0} gauge`n" -f $name
$results += $result1
$results += $result2
 
foreach($ConfiguredQuota in $ConfiguredQuotas)
    {
 
    $quotaName = $null
    $type = $null
 
 
    $quotaName = $ConfiguredQuota.name.Replace(" ","_").ToLower()
    $type = $ConfiguredQuota.type
     
    foreach($propertyQuota in $ConfiguredQuota)
        {  
        $location = $null
        $helperPropertyQuota = $null
 
        $location = $propertyQuota.location 
        $helperPropertyQuota = $propertyQuota.properties | Get-member -MemberType NoteProperty
 
        foreach($p in $helperPropertyQuota)
            {
            $valueName = $null
            $value = $null           
             
            $valueName = $p.name
            $value = $propertyQuota.properties
            $value = $value.$valueName
 
            $result3 = "azs_{0}{{location=`"{1}`",quotaName=`"{2}`",valueName=`"{3}`",type=`"{4}`"}} {5}`n" -f @($name, $location, $quotaName, $valueName, $type, $value)
            $results += $result3
            }
         
         
        }
    }
 
$responseConfiguredQuotas = Invoke-WebRequest -Uri "http://localhost:9091/metrics/job/$jobname/instance/$stamp" -Method Post -Body $results
#endregion
 
#region List Service Health through API
$ListServiceHealths = "$ArmEndPoint/subscriptions/$adminSubscription/resourceGroups/System.$stamp/providers/Microsoft.InfrastructureInsights.Admin/regionHealths/$stamp/serviceHealths?api-version=2016-05-01"
$ServiceHealths = (Invoke-RestMethod -Uri $ListServiceHealths -ContentType "application/json" -Headers $Headers -Method Get -Debug -Verbose).value
 
$results = $null
$name = $null
$name = "service_health"
 
$result1 = "#HELP {0} 0=healthy, 1=warning, 2=critical, 3=unknownm, 4=something else happened`n" -f $name
$result2 = "#TYPE {0} gauge`n" -f $name
$results += $result1
$results += $result2
 
foreach($ServiceHealth in $ServiceHealths)
    {
 
    $serviceName = $null
    $type = $null
 
 
    $serviceName = $ServiceHealth.name.Replace(" ","_").ToLower()
    $type = $ServiceHealth.type
     
    foreach($propertyHealth in $ServiceHealth)
        {  
        $location = $null
        $helperpropertyHealth = $null
        $valueName = $null
        $value = $null           
 
        $location = $propertyHealth.location 
        $helperpropertyHealth = $propertyHealth.properties | Get-member -MemberType NoteProperty
             
        $displayName = $serviceHealth.properties.displayName
        $value = $propertyHealth.properties.healthstate
 
        switch ( $value.ToLower() )
            {
            healthy { $value = '0' }
            warning { $value = '1' }
            critical { $value = '2' }
            unknown { $value = '3' }
            default { $value = '4' }
            }
 
 
        $result3 = "azs_{0}{{location=`"{1}`",serviceHealthName=`"{2}`",displayName=`"{3}`",type=`"{4}`"}} {5}`n" -f @($name, $location, $serviceName, $displayName, $type, $value)
        $results += $result3
         
        }
    }
 
$responseServiceHealths = Invoke-WebRequest -Uri "http://localhost:9091/metrics/job/$jobname/instance/$stamp" -Method Post -Body $results
#endregion
 
#region List of Subscriptions through API
$ListSubscriptions = "$ArmEndPoint/subscriptions/$adminSubscription/providers/Microsoft.Subscriptions.Admin/subscriptions?api-version=2015-11-01"
 
$Subscriptions = (Invoke-RestMethod -Uri $ListSubscriptions -ContentType "application/json" -Headers $Headers -Method Get -Debug -Verbose).value
 
$results = $null
$name = $null
$name = "user_subscriptions"
$location = $stamp
 
$result1 = "#HELP {0} Get all User Subscriptions that exist and get the state of the user subscription. 0=disabled, 1=enabled, 4=something else happened`n" -f $name
$result2 = "#TYPE {0} gauge`n" -f $name
$results += $result1
$results += $result2
 
foreach($subscription in $Subscriptions)
    {
 
    $id = $null
    $subscriptionId = $null
    $delegatedProviderSubscriptionId = $null
    $displayName = $null
    $owner = $null
    $tenantId = $null
    $routingResourceManagerType = $null
    $offerId = $null
    $state = $null
 
    $id = $subscription.id
    $subscriptionId = $subscription.subscriptionId
    $delegatedProviderSubscriptionId = $subscription.delegatedProviderSubscriptionId
    $displayName = $subscription.displayName
    $owner = $subscription.owner
    $tenantId = $subscription.tenantId
    $routingResourceManagerType = $subscription.routingResourceManagerType
    $offerId = $subscription.offerId
    $state = $subscription.state
 
        switch ( $state.ToLower() )
            {
            disabled { $state = '0' }
            enabled { $state = '1' }
            default { $state = '4' }
            }
 
    $result3 = "azs_{0}{{location=`"{1}`",id=`"{2}`",subscriptionId=`"{3}`",delegatedProviderSubscriptionId=`"{4}`",displayName=`"{5}`",owner=`"{6}`",tenantId=`"{7}`",routingResourceManagerType=`"{8}`",offerId=`"{9}`"}} {10}`n" -f @($name, $location, $id, $subscriptionId, $delegatedProviderSubscriptionId, $displayName, $owner, $tenantId, $routingResourceManagerType, $offerId, $state)
    $results += $result3
     
 
    }
 
$responseListSubscriptions = Invoke-WebRequest -Uri "http://localhost:9091/metrics/job/$jobname/instance/$stamp" -Method Post -Body $results
#endregion
 
Stop-Transcript
