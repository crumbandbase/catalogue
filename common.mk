.SUFFIXES: .csr .pem .conf
.PRECIOUS: %/ca-key.pem %/ca-cert.pem %/cert-chain.pem
.PRECIOUS: %/workload-cert.pem %/key.pem %/workload-cert-chain.pem
.PRECIOUS: %/install.sh %/workloadgroup.yaml
.SECONDARY: root-cert.csr root-ca.conf %/cluster-ca.csr %/intermediate.conf

.DEFAULT_GOAL := help

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

#------------------------------------------------------------------------
##help:                   print this help message
.PHONY: help

help:
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/##//'

#------------------------------------------------------------------------
# variables: istio
ISTIO_VERSION ?= 1.16.4
ISTIO_REVISION ?= 1-16-4

#------------------------------------------------------------------------
# variables: root CA
ROOTCA_DAYS ?= 3650
ROOTCA_KEYSZ ?= 4096
ROOTCA_ORG ?= Istio
ROOTCA_CN ?= Root CA
KUBECONFIG ?= $(HOME)/.kube/config
ISTIO_NAMESPACE ?= istio-system
# Additional variables are defined in root-ca.conf target below.

#------------------------------------------------------------------------
# variables: intermediate CA
INTERMEDIATE_DAYS ?= 730
INTERMEDIATE_KEYSZ ?= 4096
INTERMEDIATE_ORG ?= Istio
INTERMEDIATE_CN ?= Intermediate CA
INTERMEDIATE_SAN_DNS ?= istiod.istio-system.svc
# Additional variables are defined in %/intermediate.conf target below.

#------------------------------------------------------------------------
# variables: workload certs: eg VM
WORKLOAD_DAYS ?= 1
WORKLOAD_NAME ?= workload
WORKLOAD_NAMESPACE ?= default
SERVICE_ACCOUNT ?= default
WORKLOAD_CN ?= Workload

#------------------------------------------------------------------------
# variables: files to clean
FILES_TO_CLEAN+=k8s-root-cert.pem \
                 k8s-root-cert.srl \
                 k8s-root-key.pem root-ca.conf root-cert.csr root-cert.pem root-cert.srl root-key.pem

#------------------------------------------------------------------------
##<name>-workloadentry: 	generate all the required configuration files for a workload instance running on a VM or non-Kubernetes environment.
.PHONY: %-workloadentry

%-workloadentry: %/workloadgroup.yaml %/install.sh
	@istioctl x workload entry configure -f $< -o $(dir $<) --revision $(ISTIO_REVISION) --clusterID $(CLUSTER_ID)
	@echo "done"

%/workloadgroup.yaml:
	@echo "generating $@"
	@mkdir -p $(dir $@)
	@istioctl x workload group create --name $(WORKLOAD_NAME) --namespace $(WORKLOAD_NAMESPACE) --labels app=$(WORKLOAD_NAME) --serviceAccount $(SERVICE_ACCOUNT) > $@
	@echo "    network: $(NETWORK)" >> $@ # There does not seem to be a flag to add this.

%/install.sh:
	@echo "#!/bin/env bash" > $@
	@echo "rm -v /etc/certs/* \\" >> $@
	@echo "  /var/run/secrets/tokens/istio-token \\" >> $@
	@echo "  /etc/istio/config/mesh \\" >> $@
	@echo "  /var/lib/istio/envoy/cluster.env" >> $@
	@echo "sudo mkdir -p /etc/certs" >> $@
	@echo "sudo cp root-cert.pem /etc/certs/" >> $@
	@echo "sudo mkdir -p /var/run/secrets/tokens" >> $@
	@echo "sudo cp istio-token /var/run/secrets/tokens/istio-token" >> $@
	@echo "curl -LO https://storage.googleapis.com/istio-release/releases/$(ISTIO_VERSION)/deb/istio-sidecar.deb" >> $@
	@echo "sudo dpkg -i istio-sidecar.deb" >> $@
	@echo "sudo cp mesh.yaml /etc/istio/config/mesh" >> $@
	@echo "sudo cp cluster.env /var/lib/istio/envoy/cluster.env" >> $@
	@echo "sudo mkdir -p /etc/istio/proxy" >> $@
	@echo "sudo chown -R istio-proxy \\" >> $@
	@echo "  /var/lib/istio \\" >> $@
	@echo "  /etc/certs \\" >> $@
	@echo "  /etc/istio/proxy \\" >> $@
	@echo "  /etc/istio/config \\" >> $@
	@echo "  /var/run/secrets" >> $@
	@echo "sudo systemctl restart istio" >> $@
	@echo "sudo systemctl status istio" >> $@

#------------------------------------------------------------------------
# clean
.PHONY: clean

clean: ## 		cleans all the intermediate files and folders previously generated.
	@rm -f $(FILES_TO_CLEAN)

root-ca.conf:
	@echo "[ req ]" > $@
	@echo "encrypt_key = no" >> $@
	@echo "prompt = no" >> $@
	@echo "utf8 = yes" >> $@
	@echo "default_md = sha256" >> $@
	@echo "default_bits = $(ROOTCA_KEYSZ)" >> $@
	@echo "req_extensions = req_ext" >> $@
	@echo "x509_extensions = req_ext" >> $@
	@echo "distinguished_name = req_dn" >> $@
	@echo "[ req_ext ]" >> $@
	@echo "subjectKeyIdentifier = hash" >> $@
	@echo "basicConstraints = critical, CA:true" >> $@
	@echo "keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, keyCertSign" >> $@
	@echo "[ req_dn ]" >> $@
	@echo "O = $(ROOTCA_ORG)" >> $@
	@echo "CN = $(ROOTCA_CN)" >> $@

%/intermediate.conf: L=$(dir $@)
%/intermediate.conf:
	@echo "[ req ]" > $@
	@echo "encrypt_key = no" >> $@
	@echo "prompt = no" >> $@
	@echo "utf8 = yes" >> $@
	@echo "default_md = sha256" >> $@
	@echo "default_bits = $(INTERMEDIATE_KEYSZ)" >> $@
	@echo "req_extensions = req_ext" >> $@
	@echo "x509_extensions = req_ext" >> $@
	@echo "distinguished_name = req_dn" >> $@
	@echo "[ req_ext ]" >> $@
	@echo "subjectKeyIdentifier = hash" >> $@
	@echo "basicConstraints = critical, CA:true, pathlen:0" >> $@
	@echo "keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, keyCertSign" >> $@
	@echo "subjectAltName=@san" >> $@
	@echo "[ san ]" >> $@
	@echo "DNS.1 = $(INTERMEDIATE_SAN_DNS)" >> $@
	@echo "[ req_dn ]" >> $@
	@echo "O = $(INTERMEDIATE_ORG)" >> $@
	@echo "CN = $(INTERMEDIATE_CN)" >> $@
	@echo "L = $(L:/=)" >> $@

%/workload.conf: L=$(dir $@)
%/workload.conf:
	@echo "[ req ]" > $@
	@echo "encrypt_key = no" >> $@
	@echo "prompt = no" >> $@
	@echo "utf8 = yes" >> $@
	@echo "default_md = sha256" >> $@
	@echo "default_bits = $(INTERMEDIATE_KEYSZ)" >> $@
	@echo "req_extensions = req_ext" >> $@
	@echo "x509_extensions = req_ext" >> $@
	@echo "distinguished_name = req_dn" >> $@
	@echo "[ req_ext ]" >> $@
	@echo "subjectKeyIdentifier = hash" >> $@
	@echo "basicConstraints = critical, CA:false" >> $@
	@echo "keyUsage = digitalSignature, keyEncipherment" >> $@
	@echo "extendedKeyUsage = serverAuth, clientAuth" >> $@
	@echo "subjectAltName=@san" >> $@
	@echo "[ san ]" >> $@
	@echo "URI.1 = spiffe://cluster.local/ns/$(L)sa/$(SERVICE_ACCOUNT)" >> $@
	@echo "[ req_dn ]" >> $@
	@echo "O = $(INTERMEDIATE_ORG)" >> $@
	@echo "CN = $(WORKLOAD_CN)" >> $@
	@echo "L = $(L:/=)" >> $@-
