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

# Stop on any error.
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Get binary path
$gopath = [System.Environment]::GetEnvironmentVariable("GOPATH")
$critestpath = $gopath + "/src/github.com/kubernetes-sigs/cri-tools/_output"

# Run e2e test cases
# Only run basic runtime info now because Windows images are not yet pushed.
cd $critestpath
./critest.exe -"ginkgo.focus" "Runtime info"

# Check 
if (!$?)
{
    Write-Host "critest failed!"
    exit 1
}