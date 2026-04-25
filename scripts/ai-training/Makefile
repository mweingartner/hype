# End-to-end HypeTalk fine-tuning pipeline.
#
# Run `make` (the default target is `help`) to see available stages.
# `make all` runs the full pipeline: corpus → train → fuse → package
# → eval. Each stage is incremental; re-running `make all` after a
# corpus edit re-runs every downstream stage.
#
# Typical workflow:
#   make corpus              # regenerate JSONL from seed YAMLs
#   make train               # LoRA fine-tune (1-4 hours on M5 Max)
#   make fuse                # merge LoRA into base
#   make package             # register Ollama model
#   make eval                # grade candidate vs. baseline
#   make set-default         # wire up as Hype's default model
#
# Or just `make all` to do everything sequentially.

ROOT := $(shell pwd)
OUT := $(ROOT)/out
SRC := $(ROOT)/src
PYTHON ?= /usr/bin/python3
TOOL_CATALOG := $(OUT)/tool_catalog.json
CORPUS_TRAIN := $(OUT)/train.jsonl
ADAPTERS := $(OUT)/adapters/adapters.safetensors
FUSED := $(OUT)/fused/config.json
MODELFILE := $(OUT)/Modelfile
EVAL_REPORT := $(OUT)/eval_report.json
HYPE_TOOLS_SWIFT := $(ROOT)/../../Sources/HypeCore/AI/HypeTools.swift

.DEFAULT_GOAL := help
.PHONY: help all augment corpus tool-catalog train fuse package eval set-default clean clean-augment deps

help:
	@echo "HypeTalk fine-tuning pipeline"
	@echo
	@echo "Targets:"
	@echo "  deps            Install Python dependencies (mlx-lm, pyyaml)"
	@echo "  tool-catalog    Extract Hype tool catalog from HypeTools.swift → out/tool_catalog.json"
	@echo "  augment         Parametrically 3x the seed corpus with variations"
	@echo "  corpus          Generate training JSONL from corpus/seed/*.yaml"
	@echo "  train           Run MLX-LM LoRA training"
	@echo "  fuse            Merge LoRA into base model weights"
	@echo "  package         Create Ollama model via Modelfile"
	@echo "  eval            Grade candidate vs. baseline on eval/prompts.jsonl"
	@echo "  set-default     Set the tuned model as Hype's default in UserDefaults"
	@echo "  all             Run augment → tool-catalog → corpus → train → fuse → package → eval"
	@echo "  clean           Remove generated artifacts under out/"
	@echo "  clean-augment   Remove *_aug.yaml files (forces re-augmentation)"
	@echo
	@echo "Config: edit config.yaml to change base model, LoRA hyperparams, output tag."

deps:
	@if ! $(PYTHON) -c "import mlx_lm" 2>/dev/null; then \
		    echo "Installing mlx-lm + pyyaml…"; \
		    if command -v uv >/dev/null; then \
		        uv pip install --system "mlx-lm>=0.20" pyyaml; \
		    else \
		        $(PYTHON) -m pip install --upgrade "mlx-lm>=0.20" pyyaml; \
		    fi; \
		else \
		    echo "mlx-lm already installed"; \
		fi

# Augmentation runs before corpus generation. Target marker is a
# timestamp file rather than a specific generated yaml — augmenter
# output names vary by which seeds exist.
AUG_MARKER := $(OUT)/.augmented

$(AUG_MARKER): $(SRC)/augment_corpus.py $(filter-out %_aug.yaml,$(wildcard corpus/seed/*.yaml))
	@find corpus/seed -name '*_aug.yaml' -delete
	@$(PYTHON) $(SRC)/augment_corpus.py --target 2000
	@mkdir -p $(OUT)
	@touch $(AUG_MARKER)

augment: $(AUG_MARKER)

# Tool catalog extraction: parses HypeTools.swift textually and
# dumps every tool's signature into out/tool_catalog.json. The
# training corpus depends on this so new tools added to the Swift
# source automatically flow into the training prompts. Re-runs
# whenever HypeTools.swift changes.
$(TOOL_CATALOG): $(SRC)/_extract_tools.py $(HYPE_TOOLS_SWIFT)
	@mkdir -p $(OUT)
	@$(PYTHON) $(SRC)/_extract_tools.py

tool-catalog: $(TOOL_CATALOG)

# Corpus regenerates whenever seeds (incl. augmentations), the
# generator, or the tool catalog change. The augmentation marker
# and tool catalog are both explicit dependencies.
$(CORPUS_TRAIN): $(AUG_MARKER) $(TOOL_CATALOG) $(SRC)/gen_corpus.py config.yaml
	@$(PYTHON) $(SRC)/gen_corpus.py

corpus: $(CORPUS_TRAIN)

# Training: re-runs when the corpus or config changes. Calls the
# shell runner with --force so Make doesn't stall on the
# interactive overwrite prompt.
$(ADAPTERS): $(CORPUS_TRAIN) config.yaml
	@PYTHON=$(PYTHON) bash $(SRC)/train.sh --force

train: $(ADAPTERS)

# Fusion: merges LoRA into fresh base weights.
$(FUSED): $(ADAPTERS) config.yaml
	@PYTHON=$(PYTHON) bash $(SRC)/fuse.sh --force

fuse: $(FUSED)

# Packaging: writes Modelfile and runs `ollama create`. Always re-runs
# (cheap, and the SYSTEM prompt may have changed in the guide even
# when the fused weights are unchanged).
package: $(FUSED)
	@PYTHON=$(PYTHON) bash $(SRC)/package.sh

# Eval assumes the packaged model is registered with Ollama. Always
# re-runs when invoked explicitly.
eval:
	@$(PYTHON) $(SRC)/eval.py

set-default:
	@bash $(SRC)/set_default.sh

all: augment tool-catalog corpus train fuse package eval
	@echo
	@echo "=== Pipeline complete ==="
	@echo "Tuned model registered. Run 'make set-default' to make Hype use it."

clean:
	@echo "Removing $(OUT)/…"
	@rm -rf $(OUT)
	@mkdir -p $(OUT)

clean-augment:
	@find corpus/seed -name '*_aug.yaml' -delete
	@rm -f $(AUG_MARKER)
	@echo "Augmentation cleared. Next 'make corpus' will re-augment."
