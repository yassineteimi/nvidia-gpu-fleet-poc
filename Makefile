SHELL := /bin/bash
.PHONY: help cluster argocd argocd-ui grafana-ui check-dcgm-image gpu-images up acceptance load load-stop inject-xid-dcgm capture-b capture-b-history test-rules workload workload-stop inject-xid return-to-service capture-c test-controller test-npd-rules down cost test-goodput test-time-slicing tenancy-wait tenancy tenancy-capture tenancy-stop prepull goodput goodput-status goodput-capture handover burn-in-diag burn-in burn-in-status burn-in-capture docs docs-serve lint shellcheck fmt test

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

workload:      ## Start a GPU workload for Session C to evict
	./scripts/gpu-workload.sh start

workload-stop: ## Remove the Session C GPU workload
	./scripts/gpu-workload.sh stop

inject-xid:    ## SIMULATED: write an Xid line into a node's kernel log (NODE=, XID=)
	./scripts/inject-xid.sh "$(NODE)" "$(XID)"

return-to-service: ## Gated return to service: lookback, dcgmi diag, reset, uncordon (NODE=)
	./scripts/return-to-service.sh "$(NODE)"

capture-c:     ## Capture Session C evidence for a node (NODE=, LABEL=)
	./scripts/capture-c.sh "$(NODE)" "$(LABEL)"

test-controller: ## Unit tests for the remediation controller
	cd controllers/gpu-remediator && python3 -m pytest -q

test-npd-rules: ## Test the GPU monitor through node-problem-detector's own code (needs Go)
	./scripts/test-npd-rules.sh

down:          ## Drain the GPU node, remove it from the cluster, destroy it
	./scripts/gpu-down.sh

cost:          ## Report how long the GPU node has been up and what it has cost
	./scripts/cost-report.sh

test-goodput:  ## Unit tests for the goodput trainer loop, store and analysis
	cd workloads/goodput && python3 -m pytest -q

test-time-slicing: ## Parse the time slicing config with the device plugin's own loader (needs Go)
	./scripts/test-time-slicing.sh

tenancy-wait:  ## After the time slicing commit: wait for the GPU node to advertise 4 GPUs
	./scripts/tenancy.sh wait-slicing

tenancy:       ## GPU pods in both tenants, then a third in tenant-a that the quota refuses
	./scripts/tenancy.sh start

tenancy-capture: ## Capture the time slicing and tenancy evidence
	./scripts/tenancy.sh capture

tenancy-stop:  ## Remove the tenant GPU pods
	./scripts/tenancy.sh stop

prepull:       ## Pull the trainer image onto the GPU node, timed
	./scripts/goodput.sh prepull

goodput:       ## Start the goodput training Job in tenant-a
	./scripts/goodput.sh start

goodput-status: ## Where the goodput Job and its pods are
	./scripts/goodput.sh status

goodput-capture: ## After the Job completes: step logs, Job timestamps, goodput
	./scripts/goodput.sh capture

handover:      ## Read-only handover check on the GPU node: versions, PCIe, ECC history, telemetry
	./scripts/handover.sh

burn-in-diag:  ## dcgmi diag -r 3 on the GPU node, timed (LABEL=before|after)
	./scripts/burn-in.sh diag "$(LABEL)"

burn-in:       ## Start the 3 hour burn-in load; it stops by itself
	./scripts/burn-in.sh start

burn-in-status: ## Where the burn-in Job is
	./scripts/burn-in.sh status

burn-in-capture: ## After the burn-in: the stability record from Prometheus
	./scripts/burn-in.sh capture

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
