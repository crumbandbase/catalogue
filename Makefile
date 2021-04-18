include $(SELF_DIR)common.mk

#------------------------------------------------------------------------
##fetch-root-ca:          fetch root CA and key from a k8s cluster.
.PHONY: fetch-root-ca
rawcluster := $(shell kubectl config current-context)
cluster := $(subst /,-,$(rawcluster))
pwd := $(shell pwd)
export KUBECONFIG

fetch-root-ca:
	@echo "fetching root ca from k8s cluster: "$(cluster)""
	@mkdir -p $(pwd)/$(cluster)
	@res=$(shell kubectl get secret istio-ca-secret -n $(ISTIO-NAMESPACE) >/dev/null 2>&1;  echo $$?)
ifeq ($(res), 1)
	@kubectl get secret cacerts -n $(ISTIO_NAMESPACE) -o "jsonpath={.data['ca-cert\.pem']}" | base64 -d > $(cluster)/k8s-root-cert.pem
	@kubectl get secret cacerts -n $(ISTIO_NAMESPACE) -o "jsonpath={.data['ca-key\.pem']}" | base64 -d > $(cluster)/k8s-root-key.pem
else
	@kubectl get secret istio-ca-secret -n $(ISTIO_NAMESPACE) -o "jsonpath={.data['ca-cert\.pem']}" | base64 -d > $(cluster)/k8s-root-cert.pem
	@kubectl get secret istio-ca-secret -n $(ISTIO_NAMESPACE) -o "jsonpath={.data['ca-key\.pem']}" | base64 -d > $(cluster)/k8s-root-key.pem
endif

#------------------------------------------------------------------------
##<name>-cacerts:         generate intermediate certificates for a cluster or VM with <name> signed with istio root cert from the specified k8s cluster and store them under <name> directory
.PHONY: %-cacerts

%-cacerts: %/cert-chain.pem
	@echo "done"

%/cert-chain.pem: %/ca-cert.pem
	@echo "generating $@"
	@cat $^ > $@
	@echo "Intermediate certs stored in $(dir $<)"
	@cp $(cluster)/k8s-root-cert.pem $(dir $<)/root-cert.pem

%/ca-cert.pem: %/cluster-ca.csr
	@echo "generating $@"
	@openssl x509 -req -days $(INTERMEDIATE_DAYS) \
		-CA $(cluster)/k8s-root-cert.pem -CAkey $(cluster)/k8s-root-key.pem -CAcreateserial\
		-extensions req_ext -extfile $(dir $<)/intermediate.conf \
		-in $< -out $@

%/cluster-ca.csr: L=$(dir $@)
%/cluster-ca.csr: %/ca-key.pem %/intermediate.conf
	@echo "generating $@"
	@openssl req -new -config $(L)/intermediate.conf -key $< -out $@

%/ca-key.pem: fetch-root-ca
	@echo "generating $@"
	@mkdir -p $(dir $@)
	@openssl genrsa -out $@ 4096

#------------------------------------------------------------------------
##<namespace>-certs:      generate intermediate certificates and sign certificates for a virtual machine connected to the namespace `<namespace> using serviceAccount `$SERVICE_ACCOUNT` using root cert from k8s cluster.
.PHONY: %-certs

%-certs: %/workload-cert-chain.pem
	@echo "done"

%/workload-cert-chain.pem: %/ca-cert.pem %/workload-cert.pem
	@echo "generating $@"
	@cat $(cluster)/k8s-root-cert.pem $^ > $@
	@echo "Intermediate and workload certs stored in $(dir $<)"
	@cp $(cluster)/k8s-root-cert.pem $(dir $<)/root-cert.pem

%/workload-cert.pem: %/workload.csr
	@echo "generating $@"
	@openssl x509 -req -days $(WORKLOAD_DAYS) \
		-CA $(dir $<)/ca-cert.pem -CAkey $(dir $<)/ca-key.pem -CAcreateserial\
		-extensions req_ext -extfile $(dir $<)/workload.conf \
		-in $< -out $@

%/workload.csr: L=$(dir $@)
%/workload.csr: %/key.pem %/workload.conf
	@echo "generating $@"
	@openssl req -new -config $(L)/workload.conf -key $< -out $@

%/key.pem:
	@echo "generating $@"
	@mkdir -p $(dir $@)
	@openssl genrsa -out $@ 4096
