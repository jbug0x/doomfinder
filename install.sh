#!/usr/bin/env bash
#
# install.sh - Instalador do DomFinder
# Instala dependências (curl, jq, go, subfinder, assetfinder, amass),
# copia o domfinder para ~/.local/bin e garante que esse dir está no PATH.
#
# criado por jbug0x
#

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_BIN_DIR="$HOME/.local/bin"
TARGET_NAME="domfinder"
SOURCE_SCRIPT="$SCRIPT_DIR/domfinder.sh"
GOBIN_DIR="$HOME/go/bin"

banner() {
    cat <<'BANNER'

 ____                _____ _           _
|  _ \  ___  _ __ ___|  ___(_)_ __   __| | ___ _ __
| | | |/ _ \| '_ ` _ \ |_  | | '_ \ / _` |/ _ \ '__|
| |_| | (_) | | | | | |  _| | | | | | (_| |  __/ |
|____/ \___/|_| |_| |_|_|   |_|_| |_|\__,_|\___|_|

              installer - criado por jbug0x
BANNER
}

log()  { echo "[*] $*"; }
ok()   { echo "[+] $*"; }
warn() { echo "[!] $*"; }
err()  { echo "[x] $*" >&2; }

# ---------- 0. Checa se domfinder.sh existe ----------
if [ ! -f "$SOURCE_SCRIPT" ]; then
    err "Não encontrei $SOURCE_SCRIPT"
    err "Rode este install.sh na mesma pasta onde está o domfinder.sh"
    exit 1
fi

# ---------- 1. Detecta gerenciador de pacotes ----------
PKG_MANAGER=""
if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
elif command -v brew >/dev/null 2>&1; then
    PKG_MANAGER="brew"
else
    warn "Não identifiquei um gerenciador de pacotes suportado (apt/dnf/yum/pacman/brew)."
    warn "Você vai precisar instalar curl, jq e golang manualmente."
fi

install_pkg() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt)    sudo apt-get install -y "$pkg" ;;
        dnf)    sudo dnf install -y "$pkg" ;;
        yum)    sudo yum install -y "$pkg" ;;
        pacman) sudo pacman -S --noconfirm "$pkg" ;;
        brew)   brew install "$pkg" ;;
        *)      return 1 ;;
    esac
}

# ---------- 2. Instala dependências de sistema (curl, jq, git, go) ----------
log "Verificando dependências de sistema ..."

if [ -n "$PKG_MANAGER" ] && [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get update -y
fi

for bin in curl jq git; do
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin já instalado."
    else
        log "Instalando $bin ..."
        if ! install_pkg "$bin"; then
            err "Falha ao instalar $bin. Instale manualmente e rode este script de novo."
            exit 1
        fi
    fi
done

# Go é necessário para compilar subfinder/assetfinder/amass
if command -v go >/dev/null 2>&1; then
    ok "go já instalado ($(go version))."
else
    log "Instalando go ..."
    case "$PKG_MANAGER" in
        apt)    install_pkg golang-go ;;
        dnf)    install_pkg golang ;;
        yum)    install_pkg golang ;;
        pacman) install_pkg go ;;
        brew)   install_pkg go ;;
        *)
            err "Não consegui instalar go automaticamente."
            err "Instale manualmente: https://go.dev/doc/install"
            exit 1
            ;;
    esac
fi

# Garante GOBIN no PATH da sessão atual (necessário pra rodar 'go install' e achar os binários depois)
export PATH="$PATH:$GOBIN_DIR"

# ---------- 3. Instala subfinder, assetfinder, amass via go install ----------
log "Verificando subfinder, assetfinder e amass ..."

if command -v subfinder >/dev/null 2>&1; then
    ok "subfinder já instalado."
else
    log "Instalando subfinder ..."
    go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
fi

if command -v assetfinder >/dev/null 2>&1; then
    ok "assetfinder já instalado."
else
    log "Instalando assetfinder ..."
    go install -v github.com/tomnomnom/assetfinder@latest
fi

if command -v amass >/dev/null 2>&1; then
    ok "amass já instalado."
else
    log "Instalando amass ..."
    go install -v github.com/owasp-amass/amass/v4/...@master
fi

# ---------- 4. Copia o domfinder para ~/.local/bin ----------
log "Instalando o DomFinder em $INSTALL_BIN_DIR ..."
mkdir -p "$INSTALL_BIN_DIR"
cp "$SOURCE_SCRIPT" "$INSTALL_BIN_DIR/$TARGET_NAME"
chmod +x "$INSTALL_BIN_DIR/$TARGET_NAME"
ok "Copiado para $INSTALL_BIN_DIR/$TARGET_NAME"

# ---------- 5. Garante que ~/.local/bin e ~/go/bin estão no PATH permanente ----------
PATH_LINE_LOCAL='export PATH="$HOME/.local/bin:$PATH"'
PATH_LINE_GO='export PATH="$HOME/go/bin:$PATH"'

RC_FILES=()
[ -n "${BASH_RC:-}" ] && RC_FILES+=("$BASH_RC")
[ -f "$HOME/.bashrc" ] && RC_FILES+=("$HOME/.bashrc")
[ -f "$HOME/.zshrc" ]  && RC_FILES+=("$HOME/.zshrc")

# remove duplicatas
RC_FILES=($(printf "%s\n" "${RC_FILES[@]}" | sort -u))

if [ "${#RC_FILES[@]}" -eq 0 ]; then
    warn "Não encontrei ~/.bashrc nem ~/.zshrc."
    echo
    echo "    Você não tem nenhum arquivo de configuração de shell ainda."
    echo "    Sugestão: descubra seu shell atual com 'echo \$SHELL' e crie o arquivo:"
    echo "      - se for bash : touch ~/.bashrc"
    echo "      - se for zsh  : touch ~/.zshrc"
    echo
    echo "    Depois adicione estas duas linhas nele:"
    echo "      $PATH_LINE_LOCAL"
    echo "      $PATH_LINE_GO"
    echo
else
    for rc in "${RC_FILES[@]}"; do
        CHANGED=false

        if ! grep -qF "$PATH_LINE_LOCAL" "$rc" 2>/dev/null; then
            {
                echo ""
                echo "# DomFinder - garante ~/.local/bin no PATH"
                echo "$PATH_LINE_LOCAL"
            } >> "$rc"
            CHANGED=true
        fi

        if ! grep -qF "$PATH_LINE_GO" "$rc" 2>/dev/null; then
            {
                echo "# DomFinder - garante ~/go/bin no PATH (subfinder/assetfinder/amass)"
                echo "$PATH_LINE_GO"
            } >> "$rc"
            CHANGED=true
        fi

        if $CHANGED; then
            ok "PATH atualizado em $rc"
        else
            ok "$rc já estava configurado."
        fi
    done
fi

echo
banner
ok "Instalação concluída!"
echo
echo "    Para usar agora nesta sessão, rode:"
echo "      export PATH=\"\$HOME/.local/bin:\$HOME/go/bin:\$PATH\""
echo
echo "    Nas próximas sessões (novo terminal) já vai funcionar direto:"
echo "      domfinder -d stripchat.com -o all_subs.txt"
echo
