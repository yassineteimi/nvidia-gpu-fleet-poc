SHELL := /bin/bash
.PHONY: help cluster argocd argocd-ui up down cost burn-in docs docs-serve lint shellcheck fmt test

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

cluster:       ## Create the private network and the persistent control plane node
	./scripts/cluster-up.sh

argocd:        ## Install ArgoCD and point it at this repository
	./scripts/bootstrap-argocd.sh

argocd-ui:     ## Print the ArgoCD admin credentials and port-forward the UI
	./scripts/argocd-ui.sh

up:            ## Create the GPU node, join it to the cluster, wait for nvidia.com/gpu
	./scripts/gpu-up.sh

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

test:          ## Run the remediation controller unit tests, no cluster needed
	.venv/bin/python -m pytest controllers/gpu-remediator/tests -q
