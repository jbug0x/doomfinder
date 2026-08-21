#!/usr/bin/env bash
#
# recon_subs.sh - Enumeração de subdomínios (passive recon) para bug bounty
# DomFinder - by jbug0x
#

# Reexecuta em bash caso tenha sido chamado com sh/dash (evita erro de [[ ]])
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

VERSION="1.1.0"

DOMAIN=""
VT_API_KEY=""
OUTPUT_FILE=""
VERBOSE=false

banner() {
    cat <<'BANNER'

 ____                _____ _           _           
|  _ \  ___  _ __ ___|  ___(_)_ __   __| | ___ _ __ 
| | | |/ _ \| '_ ` _ \ |_  | | '_ \ / _` |/ _ \ '__|
| |_| | (_) | | | | | |  _| | | | | | (_| |  __/ |   
|____/ \___/|_| |_| |_|_|   |_|_| |_|\__,_|\___|_|   

                                     criado por jbug0x
BANNER
}

usage() {
    banner
    cat <<USAGE
DomFinder v${VERSION}

Uso: $0 -d <dominio.com> -o <arquivo_final> [-VT <VT_API_KEY>] [-vv]

  -d, --domain          Domínio alvo (obrigatório) (ex: stripchat.com)
  -o, --output          Caminho do arquivo final consolidado (ex: /Documentos/all.txt)
  -VT, --vt-api         API key do VirusTotal (opcional; se ausente, essa etapa é pulada)
  -vv                   Gera os arquivos intermediários no mesmo diretório do -o
                         (por padrão eles ficam em um dir temporário sob /tmp)
  -h, --help            Mostra esta ajuda
  --version             Mostra a versão

Exemplos:
  $0 -d example.com -o /Documentos/all.txt
  $0 -d example.com -o /Documentos/all.txt -VT abc123
  $0 -d example.com -o /Documentos/all.txt -VT abc123 -vv
USAGE
    exit 0
}

version() {
    echo "DomFinder v${VERSION} - por jbug0x"
    exit 0
}

check_deps() {
    local missing=""

    for bin in curl jq subfinder assetfinder amass; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            missing="$missing $bin"
        fi
    done

    if [ -n "$missing" ]; then
        echo "[!] Ferramentas faltando:$missing"
        echo "[!] Instale-as antes de continuar."
        exit 1
    fi
}

# ---------- Parse manual dos argumentos ----------
while [ $# -gt 0 ]; do
    case "$1" in
        -d|--domain) DOMAIN="$2"; shift 2 ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        -VT|--vt-api) VT_API_KEY="$2"; shift 2 ;;
        -vv) VERBOSE=true; shift ;;
        -h|--help) usage ;;
        --version) version ;;
        *) echo "[!] Opção desconhecida: $1"; usage ;;
    esac
done

banner
check_deps

if [ -z "$DOMAIN" ]; then
    echo "[!] Domínio (-d) é obrigatório."
    usage
fi

if [ -z "$OUTPUT_FILE" ]; then
    echo "[!] Arquivo de saída (-o) é obrigatório."
    usage
fi

# ---------- Define onde os arquivos intermediários serão gerados ----------
if $VERBOSE; then
    WORKDIR="$(dirname "$OUTPUT_FILE")"
    mkdir -p "$WORKDIR"
    CLEANUP=false
else
    WORKDIR="$(mktemp -d /tmp/domfinder_XXXXXX)"
    CLEANUP=true
fi

# garante que o diretório do arquivo final existe
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "[*] Domínio alvo        : $DOMAIN"
echo "[*] Arquivos intermed.  : $WORKDIR"
echo "[*] Arquivo final       : $OUTPUT_FILE"
if [ -z "$VT_API_KEY" ]; then
    echo "[*] VirusTotal          : desativado (nenhuma key informada)"
fi
echo

# ---------- crt.sh ----------
echo "[*] Consultando crt.sh ..."
CRTSH_RAW=""
CRTSH_TRIES=3
CRTSH_WAIT=5
for i in $(seq 1 "$CRTSH_TRIES"); do
    CRTSH_RAW="$(curl -s --max-time 30 "https://crt.sh/?q=%25.${DOMAIN}&output=json")"
    if [ -n "$CRTSH_RAW" ] && echo "$CRTSH_RAW" | jq -e . >/dev/null 2>&1; then
        break
    fi
    if [ "$i" -lt "$CRTSH_TRIES" ]; then
        echo "    [!] crt.sh não respondeu com JSON válido (tentativa $i/$CRTSH_TRIES). Aguardando ${CRTSH_WAIT}s..."
        sleep "$CRTSH_WAIT"
        CRTSH_WAIT=$((CRTSH_WAIT * 2))
    fi
done

if [ -n "$CRTSH_RAW" ] && echo "$CRTSH_RAW" | jq -e . >/dev/null 2>&1; then
    echo "$CRTSH_RAW" | jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u > "$WORKDIR/crtsh.txt"
else
    echo "    [!] crt.sh indisponível após $CRTSH_TRIES tentativas. Pulando essa fonte."
    : > "$WORKDIR/crtsh.txt"
fi

# ---------- subfinder ----------
echo "[*] Rodando subfinder ..."
subfinder -d "$DOMAIN" -all -silent > "$WORKDIR/subfinder.txt"

# ---------- assetfinder ----------
echo "[*] Rodando assetfinder ..."
assetfinder --subs-only "$DOMAIN" > "$WORKDIR/assetfinder.txt"

# ---------- amass ----------
echo "[*] Rodando amass (passive) ..."
amass enum -passive -d "$DOMAIN" -o "$WORKDIR/amass.txt"

# ---------- VirusTotal (opcional) ----------
if [ -n "$VT_API_KEY" ]; then
    echo "[*] Consultando VirusTotal ..."
    VT_RAW="$(curl -s --max-time 30 "https://www.virustotal.com/vtapi/v2/domain/report?apikey=${VT_API_KEY}&domain=${DOMAIN}")"
    if [ -n "$VT_RAW" ] && echo "$VT_RAW" | jq -e . >/dev/null 2>&1; then
        echo "$VT_RAW" | jq -r '.subdomains[]?' > "$WORKDIR/vt.txt"
    else
        echo "[!] VirusTotal não retornou JSON válido (key inválida, limite excedido ou indisponível). Pulando essa fonte."
        : > "$WORKDIR/vt.txt"
    fi
else
    : > "$WORKDIR/vt.txt"
fi

# ---------- Merge final ----------
echo "[*] Consolidando resultados ..."
cat "$WORKDIR/crtsh.txt" "$WORKDIR/subfinder.txt" "$WORKDIR/assetfinder.txt" "$WORKDIR/amass.txt" "$WORKDIR/vt.txt" | sort -u > "$OUTPUT_FILE"

echo "[+] Total de subdomínios únicos: $(wc -l < "$OUTPUT_FILE")"
echo "[+] Resultado final em: $OUTPUT_FILE"

# ---------- Limpeza (só remove se não for modo -vv) ----------
if $CLEANUP; then
    rm -rf "$WORKDIR"
fi
