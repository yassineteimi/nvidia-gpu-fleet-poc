SHELL := /bin/bash
.PHONY: help cluster argocd argocd-ui grafana-ui check-dcgm-image gpu-images up acceptance load load-stop inject-xid-dcgm capture-b capture-b-history test-rules down cost burn-in docs docs-serve lint shellcheck fmt test

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

cluster:       ## Create the private network and the persistent control plane node
	./scripts/cluster-up.sh

argocd:        ## Install ArgoCD and point it at this repository
	./scripts/bootstrap-argocd.sh

argocd-ui:     ## Print the ArgoCD admin credentials and port-forward the UI
	./scripts/argocd-ui.sh

grafana-ui:    ## Print the Grafana admin credentials and port-forward the UI
	./scripts/grafana-ui.sh

check-dcgm-image: ## Free check, no GPU: does the DCGM image carry the B2 tools
	./scripts/check-dcgm-image.sh

gpu-images:    ## List the images Scaleway will boot on the GPU node type
	./scripts/gpu-images.sh

up:            ## Create the GPU node, join it to the cluster, wait for nvidia.com/gpu
	./scripts/gpu-up.sh

acceptance:    ## Run the Session A CUDA acceptance test and save the evidence
	./scripts/acceptance.sh

load:          ## Start real tensor load on the GPU (Session B)
	./scripts/load.sh start

load-stop:     ## Kill the load job, which the collapse alert should catch
	./scripts/load.sh stop

inject-xid-dcgm: ## SIMULATED: inject XID 79 into DCGM's cache on the GPU node
	./scripts/inject-xid-dcgm.sh 79

capture-b:     ## Capture Session B evidence from Prometheus and Alertmanager
	./scripts/capture-b.sh

capture-b-history: ## After make down: check the GPU's metrics history survived
	./scripts/capture-b.sh history

down:          ## Drain the GPU node, remove it from the cluster, destroy it
	./scripts/gpu-down.sh

cost:          ## Report how long the GPU node has been up and what it has cost
	./scripts/cost-report.sh

burn-in:       ## Run the burn-in loop and record the stability log
	./scripts/burn-in.sh

docs-serve:    ## Serve the documentation site locally
	.venv/bin/mkdocs serve

docs:          ## Build the documentation site strictly
	.venv/bin/mkdocs build --strict

lint:          ## Fail if an em dash has crept into the repository
	@dash=$$(printf '\xe2\x80\x94'); \
	if grep -rn "$$dash" --exclude-dir=.git --exclude-dir=.venv --exclude-dir=site .; then \
	  echo "em dash found, see above"; exit 1; \
	fi
	@echo "no em dashes"

shellcheck:    ## Static check every shell script in scripts/
	@shellcheck --severity=warning --external-sources scripts/*.sh
	@echo "shellcheck clean"

fmt:           ## Format and check the Terraform
	@terraform -chdir=terraform fmt -check -diff

test-rules:    ## Unit test the alert rules with promtool, no cluster needed
	./scripts/test-rules.sh

test:          ## Run the remediation controller unit tests, no cluster needed
	.venv/bin/python -m pytest controllers/gpu-remediator/tests -q
