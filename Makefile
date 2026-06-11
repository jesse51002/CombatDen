# Flatpak meld can't see the host /tmp (sandbox-private), so difftool's
# staging dirs must live somewhere under $HOME.
MELD_TMP = $$HOME/.cache/git-difftool

.PHONY: setup-meld meld meld-origin meld-branch

setup-meld:
	flatpak install -y flathub org.gnome.meld
	git config --global diff.tool meld
	git config --global difftool.meld.cmd 'flatpak run org.gnome.meld "$$LOCAL" "$$REMOTE"'

# Diff this checkout's working tree against the root codebase checkout
# (the main working tree that worktrees in .claude/worktrees/ share).
meld:
	@root="$$(dirname "$$(git rev-parse --path-format=absolute --git-common-dir)")"; \
	base="$$(git -C "$$root" rev-parse HEAD)"; \
	echo "Diffing against root checkout $$(git -C "$$root" rev-parse --abbrev-ref HEAD) @ $${base:0:9} ($$root)"; \
	mkdir -p "$(MELD_TMP)"; \
	TMPDIR="$(MELD_TMP)" git difftool -d "$$base"

# Diff this checkout's working tree against the remote main (fetches first).
meld-origin:
	git fetch origin main
	@mkdir -p "$(MELD_TMP)"; \
	TMPDIR="$(MELD_TMP)" git difftool -d origin/main

# Diff this checkout's working tree against the CURRENT branch's remote
# version (fetches first) — i.e. everything local that origin doesn't have yet.
meld-branch:
	@branch="$$(git rev-parse --abbrev-ref HEAD)"; \
	git fetch origin "$$branch"; \
	echo "Diffing against origin/$$branch"; \
	mkdir -p "$(MELD_TMP)"; \
	TMPDIR="$(MELD_TMP)" git difftool -d "origin/$$branch"
