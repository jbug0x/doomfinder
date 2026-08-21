#!/usr/bin/env bash
#
# install.sh - Instalador do DomFinder
# Instala dependências (curl, jq, go, subfinder, assetfinder, amass, httpx),
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

# Pergunta y/n ao usuário. Uso: ask_yes_no "pergunta" "default(y|n)"
# Lê de /dev/tty para funcionar mesmo se o script for chamado via pipe (ex: curl | bash)
ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local hint="[Y/n]"
    local answer

    [ "$default" = "n" ] && hint="[y/N]"

    if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        # sem terminal interativo disponível, usa o default
        [ "$default" = "y" ] && return 0 || return 1
    fi

    read -r -p "$prompt $hint " answer < /dev/tty
    answer="${answer:-$default}"
    case "$answer" in
        y|Y|s|S|sim|yes) return 0 ;;
        *) return 1 ;;
    esac
}

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

# Mapeia binário -> nome do pacote (nem sempre é igual, ex: go)
pkg_name_for() {
    local bin="$1"
    case "$bin" in
        go)
            case "$PKG_MANAGER" in
                apt) echo "golang-go" ;;
                *)   echo "go" ;;
            esac
            ;;
        *) echo "$bin" ;;
    esac
}

# ---------- 2. Verifica o que falta e pergunta sobre uso de sudo ----------
log "Verificando dependências de sistema ..."

MISSING_DEPS=""
for bin in curl jq git go; do
    command -v "$bin" >/dev/null 2>&1 || MISSING_DEPS="$MISSING_DEPS $bin"
done

if [ -z "$MISSING_DEPS" ]; then
    ok "Todas as dependências de sistema (curl, jq, git, go) já estão instaladas."
else
    warn "Dependências faltando:$MISSING_DEPS"

    ALLOW_SUDO=false
    if [ -n "$PKG_MANAGER" ]; then
        if ask_yes_no "Deseja instalar essas dependências automaticamente usando sudo?" "y"; then
            ALLOW_SUDO=true
        fi
    else
        warn "Nenhum gerenciador de pacotes suportado foi detectado, então sudo não ajudaria aqui."
    fi

    if $ALLOW_SUDO && [ "$PKG_MANAGER" = "apt" ]; then
        sudo apt-get update -y
    fi

    for bin in curl jq git go; do
        command -v "$bin" >/dev/null 2>&1 && continue

        pkg="$(pkg_name_for "$bin")"

        if $ALLOW_SUDO; then
            log "Instalando $bin ..."
            if ! install_pkg "$pkg"; then
                err "Falha ao instalar $bin via $PKG_MANAGER."
                warn "Instale manualmente: $bin (pacote: $pkg)"
            fi
        else
            # sudo global recusado: pergunta individualmente para essa dependência
            if [ -n "$PKG_MANAGER" ] && ask_yes_no "  -> Instalar '$bin' agora usando root (sudo), só para essa dependência?" "n"; then
                log "Instalando $bin ..."
                if ! install_pkg "$pkg"; then
                    err "Falha ao instalar $bin via $PKG_MANAGER."
                fi
            else
                warn "Pulando $bin. Instale manualmente depois: $pkg"
            fi
        fi
    done
fi

# Garante GOBIN no PATH da sessão atual (necessário pra rodar 'go install' e achar os binários depois)
export PATH="$PATH:$GOBIN_DIR"

# ---------- 3. Instala subfinder, assetfinder, amass via go install ----------
if ! command -v go >/dev/null 2>&1; then
    warn "go não está instalado — pulando subfinder, assetfinder e amass."
    warn "Instale o go depois e rode este install.sh novamente para completar."
else
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

    if command -v httpx >/dev/null 2>&1; then
        ok "httpx já instalado."
    else
        log "Instalando httpx (usado pela flag -A/--alive do domfinder) ..."
        go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
    fi
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

RC_FILES=""
[ -f "$HOME/.bashrc" ] && RC_FILES="$RC_FILES $HOME/.bashrc"
[ -f "$HOME/.zshrc" ]  && RC_FILES="$RC_FILES $HOME/.zshrc"

if [ -z "$RC_FILES" ]; then
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
    for rc in $RC_FILES; do
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
