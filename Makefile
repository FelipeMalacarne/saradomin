DEC_SECRETS := $(shell find kubernetes -name "*.dec.yaml")
ENC_SECRETS  := $(shell find kubernetes -name "secrets.yaml")

.PHONY: encrypt decrypt

encrypt: ## Encrypt all *.dec.yaml → secrets.yaml
	@for f in $(DEC_SECRETS); do \
		out=$$(dirname "$$f")/secrets.yaml; \
		echo "Encrypting $$f → $$out"; \
		sops -e "$$f" > "$$out"; \
	done

decrypt: ## Decrypt all secrets.yaml → *.dec.yaml
	@for f in $(ENC_SECRETS); do \
		out=$$(dirname "$$f")/$$(basename "$$f" .yaml).dec.yaml; \
		echo "Decrypting $$f → $$out"; \
		sops -d "$$f" > "$$out"; \
	done
