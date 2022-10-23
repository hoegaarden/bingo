BINGO_NS ?= bingo
BINGO_APP ?= bingo-system

.PHONY: image.update
image.update:
	ytt -v bingo.namespace=$(BINGO_NS) --data-values-env-yaml BINGO -f bingo.yml -f schema.yml \
		| kbld --lock-output images.lock.yml -f kbld.yml -f -

.PHONY: install
install:
	ytt -v bingo.namespace=$(BINGO_NS) --data-values-env-yaml BINGO -f bingo.yml -f schema.yml \
		| kbld -f images.lock.yml -f kbld.yml -f - \
		| kapp deploy --namespace $(BINGO_NS) -y -a $(BINGO_APP) -f -
