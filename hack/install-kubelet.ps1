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

# Install essential tools
choco install -y mingw

# Install kubelet
mkdir -p "$env:GOPATH/src/k8s.io"
cd "$env:GOPATH/src/k8s.io"
git clone -c core.symlinks=true https://github.com/kubernetes/kubernetes
cd "$env:GOPATH/src/k8s.io/kubernetes"

if ( ! "$env:TRAVIS_BRANCH".Equals("master") ) {
  # We can do this because cri-tools have the same branch name with kubernetes.
  git checkout "$env:TRAVIS_BRANCH"
}

# Build kubelet
go build cmd\kubelet\kubelet.go

# Dump version
echo "Kubelet version:"
.\kubelet.exe --version