# Flatpak meld can't see the host /tmp (sandbox-private), so difftool's
# staging dirs must live somewhere under $HOME.
MELD_TMP = $$HOME/.cache/git-difftool

.PHONY: setup-meld meld meld-origin meld-branch meld-intent

# git diff/difftool ignores UNTRACKED files, so brand-new files would be
# invisible in the meld window. Register them with intent-to-add (-N: the
# path appears in diffs as new-vs-empty, NO content is staged). Excludes
# worktree checkouts and .venv symlinks (never to be committed).
meld-intent:
	@git ls-files --others --exclude-standard -z \
	| grep -zv -e '^\.claude/worktrees/' -e '\.venv' \
	| xargs -0r git add -N 2>/dev/null; true

setup-meld:
	flatpak install -y flathub org.gnome.meld
	git config --global diff.tool meld
	git config --global difftool.meld.cmd 'flatpak run org.gnome.meld "$$LOCAL" "$$REMOTE"'

# Diff this checkout's working tree against the root codebase checkout
# (the main working tree that worktrees in .claude/worktrees/ share).
meld: meld-intent
	@root="$$(dirname "$$(git rev-parse --path-format=absolute --git-common-dir)")"; \
	base="$$(git -C "$$root" rev-parse HEAD)"; \
	echo "Diffing against root checkout $$(git -C "$$root" rev-parse --abbrev-ref HEAD) @ $${base:0:9} ($$root)"; \
	mkdir -p "$(MELD_TMP)"; \
	TMPDIR="$(MELD_TMP)" git difftool -d "$$base"

# Diff this checkout's working tree against the remote main (fetches first).
meld-origin: meld-intent
	git fetch origin main
	@mkdir -p "$(MELD_TMP)"; \
	TMPDIR="$(MELD_TMP)" git difftool -d origin/main

# Diff this checkout's working tree against the CURRENT branch's remote
# version (fetches first) — i.e. everything local that origin doesn't have yet.
meld-branch: meld-intent
	@branch="$$(git rev-parse --abbrev-ref HEAD)"; \
	git fetch origin "$$branch"; \
	echo "Diffing against origin/$$branch"; \
	mkdir -p "$(MELD_TMP)"; \
	TMPDIR="$(MELD_TMP)" git difftool -d "origin/$$branch"
