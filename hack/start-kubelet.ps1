# Copyright 2018 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Param(
    $clusterCIDR="192.168.0.0/16",
    $podCIDR="192.168.1.0/24",
    $NetworkMode = "nat",
    $NetworkName = "nat"
)

# Stop on any error.
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Global config.
$WorkingDir = "c:\k"
$CNIPath = [Io.path]::Combine($WorkingDir , "cni")
$CNIConfig = [Io.path]::Combine($CNIPath, "config", "$NetworkMode.conf")
$endpointName = "cbr0"
$vnicName = "vEthernet ($endpointName)"

ipmo $WorkingDir\helper.psm1

function Get-PodGateway($podCIDR)
{
    # Current limitation of Platform to not use .1 ip, since it is reserved
    return $podCIDR.substring(0,$podCIDR.lastIndexOf(".")) + ".1"
}

function Get-PodEndpointGateway($podCIDR)
{
    # Current limitation of Platform to not use .1 ip, since it is reserved
    return $podCIDR.substring(0,$podCIDR.lastIndexOf(".")) + ".2"
}

function Get-MgmtIpAddress()
{
    $na = Get-NetAdapter | ? Name -Like "vEthernet (Ethernet*"
    return (Get-NetIPAddress -InterfaceAlias $na.ifAlias -AddressFamily IPv4).IPAddress
}

function ConvertTo-DecimalIP
{
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Net.IPAddress] $IPAddress
  )
  $i = 3; $DecimalIP = 0;
  $IPAddress.GetAddressBytes() | % {
    $DecimalIP += $_ * [Math]::Pow(256, $i); $i--
  }

  return [UInt32]$DecimalIP
}

function ConvertTo-DottedDecimalIP
{
  param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Uint32] $IPAddress
  )

    $DottedIP = $(for ($i = 3; $i -gt -1; $i--)
    {
      $Remainder = $IPAddress % [Math]::Pow(256, $i)
      ($IPAddress - $Remainder) / [Math]::Pow(256, $i)
      $IPAddress = $Remainder
    })

    return [String]::Join(".", $DottedIP)
}

function ConvertTo-MaskLength
{
  param(
    [Parameter(Mandatory = $True, Position = 0)]
    [Net.IPAddress] $SubnetMask
  )
    $Bits = "$($SubnetMask.GetAddressBytes() | % {
      [Convert]::ToString($_, 2)
    } )" -replace "[\s0]"
    return $Bits.Length
}

function Update-CNIConfig($podCIDR)
{
    $jsonSampleConfig = '{
  "cniVersion": "0.2.0",
  "name": "<NetworkMode>",
  "type": "wincni.exe",
  "master": "Ethernet",
  "capabilities": { "portMappings": true },
  "ipam": {
     "environment": "azure",
     "subnet":"<PODCIDR>",
     "routes": [{
        "GW":"<PODGW>"
     }]
  },
  "dns" : {
    "Nameservers" : [ "1.1.1.1" ]
  }
}'

    $configJson =  ConvertFrom-Json $jsonSampleConfig
    $configJson.name = $NetworkMode.ToLower()
    $configJson.ipam.subnet=$podCIDR
    $configJson.ipam.routes[0].GW = Get-PodEndpointGateway $podCIDR

    if (Test-Path $CNIConfig) {
        Clear-Content -Path $CNIConfig
    }

    Write-Host "Generated CNI Config [$configJson]"

    Add-Content -Path $CNIConfig -Value (ConvertTo-Json $configJson -Depth 20)
}

function Update-Docker-Version {
  $DockerVersion = docker version -f "{{.Server.Version}}"
  switch ($DockerVersion.Substring(0,5))
    {
        "17.06" {
            Write-Host "Docker 17.06 found, setting DOCKER_API_VERSION to 1.30"
            $env:DOCKER_API_VERSION = "1.30"
        }

        "18.03" {
            Write-Host "Docker 18.03 found, setting DOCKER_API_VERSION to 1.37"
            $env:DOCKER_API_VERSION = "1.37"
        }

        default {
            Write-Host "Docker version $DockerVersion found, clearing DOCKER_API_VERSION"
            $env:DOCKER_API_VERSION = $null
        }
    }
}

# startup the service
$podGW = Get-PodGateway $podCIDR
ipmo C:\k\hns.psm1

$hnsNetwork = Get-HnsNetwork | ? Name -EQ $NetworkName.ToLower()
if( !$hnsNetwork )
{
    $hnsNetwork = New-HNSNetwork -Type $NetworkMode -AddressPrefix $podCIDR -Gateway $podGW -Name $NetworkName.ToLower() -Verbose
}

# Add route to all other POD networks
Update-CNIConfig $podCIDR

Update-Docker-Version
c:\k\kubelet.exe --hostname-override=$(hostname) --v=4 `
    --pod-infra-container-image=kubeletwin/pause --resolv-conf="" `
    --allow-privileged=true --enable-debugging-handlers `
    --cluster-domain=cluster.local --keep-terminated-pod-volumes=false `
    --kubeconfig=c:\k\config --hairpin-mode=promiscuous-bridge `
    --image-pull-progress-deadline=20m --cgroups-per-qos=false `
    --log-dir=c:\k --logtostderr=true --enforce-node-allocatable="" `
    --pod-cidr=$podCIDR --experimental-dockershim --max-pods=110 `
    --network-plugin=cni --cni-bin-dir="c:\k\cni" --cni-conf-dir "c:\k\cni\config"
