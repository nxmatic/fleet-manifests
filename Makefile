FLOX_DIR ?= flox
YQ ?= yq
FLOX_REMOTE ?= origin
FLOX_BRANCH ?= flox-subtree

SHELL := bash
.SHELLFLAGS := -euxo pipefail -c
.ONESHELL:

.PHONY: update-flox check-flox-clean finalize-merge flox-refresh-locks flox-update-sync

flox-update: finalize-merge
flox-update: check-flox-clean
flox-update: flox-update-sync
flox-update: flox-refresh-locks
flox-update:
	: "[flox-update] applied"

flox-update-sync:
	git fetch --prune "$(FLOX_REMOTE)" "$(FLOX_BRANCH)"
	git subtree pull --prefix="$(FLOX_DIR)" "$(FLOX_REMOTE)" "$(FLOX_BRANCH)" --squash

check-flox-clean:
	if ! git diff --quiet -- "$(FLOX_DIR)"; then
		echo "Uncommitted changes detected inside $(FLOX_DIR). Please commit or stash them before updating." >&2;
		exit 1;
	fi
	untracked="$$(git ls-files --others --exclude-standard -- "$(FLOX_DIR)")";
	if [[ -n "$$untracked" ]]; then
		echo "Untracked files detected inside $(FLOX_DIR). Please add or clean them before updating." >&2;
		exit 1;
	fi

# Auto-commit any completed merge so batch runs do not stop for editor prompts.
finalize-merge:
	if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
		if git diff --name-only --diff-filter=U | grep -q .; then
			echo "Merge in progress with unresolved conflicts; resolve them before rerunning update-flox." >&2;
			exit 1;
		fi;
		echo "Completing pending merge with default message...";
		GIT_MERGE_AUTOEDIT=no git commit --no-edit --quiet;
	fi

flox-refresh-locks:
	@echo "Refreshing flox manifest.lock files under $(FLOX_DIR) respecting include dependencies..."
	@ROOT="$$(pwd -P)"; \
	FLOX_PATH="$$ROOT/$(FLOX_DIR)"; \
	shopt -s nullglob; \
	declare -A refreshed; \
	refresh_env() { \
		local env_dir="$$1"; \
		if [ -z "$$env_dir" ] || [ ! -d "$$env_dir/.flox" ]; then \
			return 0; \
		fi; \
		if [[ -n "${refreshed[$$env_dir]+set}" ]]; then \
			return 0; \
		fi; \
		local env_name="$$(basename "$$env_dir")"; \
		local descriptor="$$env_dir/$$env_name.yaml"; \
		local manifest="$$env_dir/.flox/env/manifest.toml"; \
		if [ -f "$$descriptor" ] && command -v $(YQ) >/dev/null 2>&1; then \
			while IFS= read -r include_dir; do \
				[ -z "$$include_dir" ] && continue; \
				case "$$include_dir" in \
					"$$FLOX_PATH"/*) refresh_env "$$include_dir" ;; \
				esac; \
			done < <($(YQ) eval '(.includes // [])[]' "$$descriptor" 2>/dev/null || true); \
		elif [ -f "$$manifest" ]; then \
			while IFS= read -r include_dir; do \
				[ -z "$$include_dir" ] && continue; \
				case "$$include_dir" in \
					"$$FLOX_PATH"/*) refresh_env "$$include_dir" ;; \
				esac; \
			done < <(sed -n "s|^[[:space:]]*dir = '\(.*\)'|\1|p" "$$manifest"); \
		fi; \
		echo "  - updating $$env_dir"; \
		flox upgrade --dir "$$env_dir" >/dev/null; \
		refreshed["$$env_dir"]=1; \
	}; \
	for env_dir in "$$FLOX_PATH"/*; do \
		refresh_env "$$env_dir"; \
	done
