# Copyright 2017 The Kubernetes Authors.
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
   $podCIDR="192.168.1.0/24"
)

# Stop on any error.
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

function BuildKubelet()
{
  Write-Host "Building kubelet"
  $gopath = [System.Environment]::GetEnvironmentVariable("GOPATH")
  $k8siopath = $gopath + "/src/k8s.io"
  $kubernetespath = $k8siopath + "/kubernetes"
  md $k8siopath -ErrorAction Ignore
  if (Test-Path $kubernetespath)
  {
      Write-Host "Using existing kubernetes repo."
  }
  else
  {
    cd $k8siopath
    git clone -c core.symlinks=true https://github.com/kubernetes/kubernetes
  }
 
  cd $kubernetespath
  $branch = [System.Environment]::GetEnvironmentVariable("TRAVIS_BRANCH")
  if ( ! "$branch".Equals("master") ) {
    # We can do this because cri-tools have the same branch name with kubernetes.
    git checkout "$branch"
  }

  # Build kubelet
  $version = git describe --tags --dirty --always
  go build -ldflags "-X k8s.io/kubernetes/vendor/k8s.io/client-go/pkg/version.gitVersion=$version -X k8s.io/kubernetes/pkg/version.gitVersion=$version" ./cmd/kubelet/kubelet.go
  cp ./kubelet.exe $BaseDir
}

function DumpKubeletVersion()
{
  # Dump version
  echo "Kubelet version:"
  C:\k\kubelet.exe --version
  echo "Docker version:"
  docker version
}

function DownloadFile()
{
    param(
        [parameter(Mandatory = $true)] $Url,
        [parameter(Mandatory = $true)] $Destination
    )

    if (Test-Path $Destination)
    {
        Write-Host "File $Destination already exists."
        return
    }

    try {
        (New-Object System.Net.WebClient).DownloadFile($Url,$Destination)
        Write-Host "Downloaded $Url=>$Destination"
    } catch {
        Write-Error "Failed to download $Url"
	    throw
    }
}

function DownloadCniBinaries()
{
    Write-Host "Downloading CNI binaries"
    md $BaseDir\cni\config -ErrorAction Ignore

    Start-BitsTransfer  https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/cni/wincni.exe -Destination $BaseDir\cni\wincni.exe
}

function DownloadWindowsKubernetesScripts()
{
    Write-Host "Downloading Windows Kubernetes scripts"
    Start-BitsTransfer  https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/hns.psm1 -Destination $BaseDir\hns.psm1
    Start-BitsTransfer  https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/windows/helper.psm1 -Destination $BaseDir\helper.psm1
}

function CopyKubeletScripts()
{
  $gopath = [System.Environment]::GetEnvironmentVariable("GOPATH")
  $critestpath = $gopath + "/src/github.com/kubernetes-sigs/cri-tools/hack/start-kubelet.ps1"
  cp $critestpath $BaseDir
}

function DownloadAllFiles()
{
    DownloadCniBinaries
    DownloadWindowsKubernetesScripts
    BuildKubelet
    CopyKubeletScripts
}

function New-InfraContainer
{
    cd C:\k
    $computerInfo = Get-ComputerInfo
    $windowsBase = if ($computerInfo.WindowsVersion -eq "1709") {
        "microsoft/nanoserver:1709"
    } elseif ($computerInfo.WindowsVersion -eq "1803") {
        "microsoft/nanoserver:1803"
    } elseif ($computerInfo.WindowsVersion -eq "1809") {
        "microsoft/nanoserver:1809"
    } else {
        "mcr.microsoft.com/nanoserver-insider"
    }

    "FROM $($windowsBase)" | Out-File -encoding ascii -FilePath Dockerfile
    "CMD cmd /c ping -t localhost" | Out-File -encoding ascii -FilePath Dockerfile -Append
    docker build -t kubeletwin/pause .
}

# Download files
$BaseDir = "c:\k"
md $BaseDir -ErrorAction Ignore
DownloadAllFiles
DumpKubeletVersion
ipmo $BaseDir\helper.psm1
ipmo $BaseDir\hns.psm1

# Prepare POD infra Images
New-InfraContainer


# WinCni needs the networkType and network name to be the same
$NetworkName = "nat"
CleanupOldNetwork $NetworkName

# Start kubelet
Start powershell -ArgumentList "-File $BaseDir\start-kubelet.ps1 -clusterCIDR $clusterCIDR -podCIDR $podCIDR -NetworkName $NetworkName"

# Wait a while for dockershim starting.
Start-Sleep 10

