# Dev image for P2-FLASH-FS.
#
# Bakes the pnut-ts compiler into a cached layer rather than installing it in
# postCreateCommand on every container create, so rebuilds are cheap and offline.
#
# ⚠️ NO HARDWARE REACHES THIS CONTAINER. Docker Desktop on macOS forwards no USB
# and the compose file passes no devices, so downloading to and running on the
# P2 board (pnut-term-ts) stays on the Mac. Compiling runs here.
#
# No apt packages are installed: the base image already provides unzip and curl,
# and image-tools-mcp needs no Tesseract/Leptonica at runtime.
FROM mcr.microsoft.com/devcontainers/javascript-node:24-bookworm

# --- git: workspace trust + baked identity -----------------------------------
# The workspace arrives over a virtiofs bind mount whose uid attribution is
# occasionally transient -- the same path can report uid 1000 one moment and a
# different uid the next with nothing changed on disk. Git's ownership check
# then refuses with "detected dubious ownership" and every git query in the tree
# fails. Intermittently, which is worse than always: it makes gates that
# discover their inputs with `git ls-files` report green having read nothing.
#
# Scoped to /workspaces/* rather than '*' so the check stays live elsewhere.
# A trailing /* matches at any depth.
RUN git config --system --add safe.directory '/workspaces/*'

# Identity is BAKED here rather than bind-mounted from the host's ~/.gitconfig.
# A single-FILE bind mount pins the source inode; macOS rewrites ~/.gitconfig by
# rename, so the container would keep reading the old, unlinked file until it is
# recreated. Directory mounts (~/.ssh, and the local override's) are immune.
#
# Only the portable subset is baked. The host config's other blocks are
# macOS-only and are inert or harmful under Linux: credential.helper=osxkeychain
# (VS Code installs its own helper), filter.lfs and filter.media with
# required=true (neither binary is installed, so any LFS-routed path fails to
# check out), and merge/difftools under /Applications.
#
# System scope, not --global: /etc/gitconfig is root-owned, baked, and survives
# a rebuild. VS Code appends its credential helper to the same file at container
# start; the two coexist.
RUN git config --system user.name 'Stephen M Moraco' \
    && git config --system user.email 'stephen@ironsheep.biz' \
    && git config --system push.default simple \
    && git config --system push.followTags false \
    && git config --system pull.rebase false

# --- ...and the system config must be the one that actually wins ------------
# The Dev Containers extension COPIES the host ~/.gitconfig into the container
# at every start. Git precedence is system < global < local, so that copy would
# outrank the bake above, and it carries the harmful blocks named there.
#
# devcontainer.json's containerEnv sets GIT_CONFIG_GLOBAL to the file created
# here, so git reads ONLY this file as global and ignores ~/.gitconfig. The copy
# still lands and is never read -- no race with the extension. Every live
# setting in the host file is already baked above, and VS Code writes its
# credential helper to both, so nothing is lost.
#
# Created here so it exists and is user-owned: a `git config --global ...` then
# lands somewhere container-local and harmless instead of re-shadowing the bake.
RUN mkdir -p /home/node/.config/git \
    && printf '%s\n' \
       '# Container-local GLOBAL git config.' \
       '#' \
       '# GIT_CONFIG_GLOBAL points here (devcontainer.json containerEnv) so that' \
       '# the host ~/.gitconfig, which the VS Code Dev Containers extension copies' \
       '# into this container at every start, is IGNORED rather than shadowing the' \
       '# identity baked into /etc/gitconfig. Put container-only overrides here;' \
       '# keeping it empty is the preference.' \
       > /home/node/.config/git/config \
    && chown -R node:node /home/node/.config

# --- pnut-ts compiler --------------------------------------------------------
# The version is discovered, not typed: the glob takes every zip present and the
# sort picks the highest, so dropping a newer zip in .devcontainer/ and
# rebuilding is the whole upgrade. The chosen zip is echoed into the build log,
# and `pnut-ts --version` runs as a build-time smoke test so a bad binary fails
# the layer rather than the first compile. The zip is gitignored.
#
# NOTE: the zip is linux-arm64 (Apple Silicon host). Re-point the COPY glob if
# building on an x64 host.
COPY pnut-ts-linux-arm64-*.zip /tmp/pnut/
RUN cd /tmp/pnut \
    && ZIP="$(ls pnut-ts-linux-arm64-*.zip | sort -V | tail -1)" \
    && echo "Baking pnut-ts from ${ZIP}" \
    && unzip -oq "$ZIP" \
    && cp "${ZIP%.zip}/pnut_ts/pnut-ts" /usr/local/bin/pnut-ts \
    && chmod +x /usr/local/bin/pnut-ts \
    && mkdir -p /opt/pnut-ts-docs \
    && find "${ZIP%.zip}/pnut_ts" -maxdepth 1 -type f \
         ! -name 'pnut-ts' ! -name 'pnut_ts' -exec cp {} /opt/pnut-ts-docs/ \; \
    && cd / && rm -rf /tmp/pnut \
    && pnut-ts --version
