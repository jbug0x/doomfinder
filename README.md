```
 ____                _____ _           _
|  _ \  ___  _ __ ___|  ___(_)_ __   __| | ___ _ __
| | | |/ _ \| '_ ` _ \ |_  | | '_ \ / _` |/ _ \ '__|
| |_| | (_) | | | | | |  _| | | | | | (_| |  __/ |
|____/ \___/|_| |_| |_|_|   |_|_| |_|\__,_|\___|_|

                     criado por jbug0x
```

# DomFinder

Script de reconhecimento passivo de subdomínios para uso em programas de **bug bounty**. Agrega resultados de várias fontes públicas em um único arquivo consolidado e sem duplicatas.

## Fontes utilizadas

- [crt.sh](https://crt.sh) — Certificate Transparency logs
- [subfinder](https://github.com/projectdiscovery/subfinder) — ProjectDiscovery
- [assetfinder](https://github.com/tomnomnom/assetfinder) — tomnomnom
- [amass](https://github.com/owasp-amass/amass) (modo passive) — OWASP
- [VirusTotal](https://www.virustotal.com) (opcional, requer API key)

Todas as consultas são **passivas** — nenhuma requisição é feita diretamente contra o domínio alvo.

## Instalação

Clone o repositório e rode o instalador:

```bash
git clone https://github.com/SEU_USUARIO/domfinder.git
cd domfinder
chmod +x install.sh domfinder.sh
./install.sh
```

O `install.sh` faz tudo automaticamente:

- Detecta seu gerenciador de pacotes (`apt`, `dnf`, `yum`, `pacman` ou `brew`)
- Instala as dependências de sistema: `curl`, `jq`, `git`, `go`
- Instala `subfinder`, `assetfinder` e `amass` via `go install` (pula o que já estiver instalado)
- Copia o script para `~/.local/bin/domfinder`
- Garante que `~/.local/bin` e `~/go/bin` estão no seu `PATH`, adicionando ao `.bashrc` e/ou `.zshrc` automaticamente
  - Se você não tiver nenhum dos dois, ele avisa e sugere o comando certo baseado no seu `$SHELL`

Depois de instalar, abra um terminal novo (ou `source ~/.bashrc` / `source ~/.zshrc`) e o comando `domfinder` já vai funcionar de qualquer diretório.

### Instalação manual (sem o install.sh)

Se preferir instalar as dependências você mesmo:

```bash
# Debian/Ubuntu/Kali
sudo apt install curl jq golang-go

# Ferramentas Go
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/tomnomnom/assetfinder@latest
go install -v github.com/owasp-amass/amass/v4/...@master

# garanta que ~/go/bin está no PATH
export PATH="$PATH:$HOME/go/bin"
```

## Uso

```
domfinder -d <dominio.com> -o <arquivo_final> [-VT <VT_API_KEY>] [-vv]
```

| Flag              | Obrigatório | Descrição                                                                 |
|-------------------|:-----------:|-----------------------------------------------------------------------------|
| `-d, --domain`    | ✅          | Domínio alvo (ex: `exemplo.com`)                                            |
| `-o, --output`    | ✅          | Caminho do arquivo final consolidado (ex: `/Documentos/all.txt`)            |
| `-VT, --vt-api`   | ❌          | API key do VirusTotal. Se omitida, essa fonte é pulada. **Evite usar essa flag** — veja abaixo |
| `-vv`             | ❌          | Mantém os arquivos intermediários (por fonte) no mesmo diretório do `-o`. Sem essa flag, eles são gerados em `/tmp` e apagados ao final |
| `-h, --help`      | ❌          | Mostra a ajuda                                                               |
| `--version`       | ❌          | Mostra a versão instalada                                                    |

### Passando a API key do VirusTotal com segurança

Passar a key direto na flag `-VT` deixa ela visível em `history` e em `ps aux` (qualquer outro usuário na máquina consegue ver enquanto o script roda). A forma recomendada é via variável de ambiente:

```bash
export DOMFINDER_VT_KEY="sua_api_key"
domfinder -d exemplo.com -o all_subs.txt
```

Se quiser que fique disponível em todas as sessões, adicione o `export` no seu `.bashrc`/`.zshrc` (fora do controle de versão, claro).

Se a flag `-VT` for usada mesmo assim, o script funciona normalmente mas emite um aviso sugerindo a variável de ambiente.

### Exemplos

```bash
# uso básico, sem VirusTotal
domfinder -d exemplo.com -o all_subs.txt

# com VirusTotal (via env var, recomendado)
export DOMFINDER_VT_KEY="sua_api_key"
domfinder -d exemplo.com -o all_subs.txt

# com VirusTotal via flag (funciona, mas gera aviso de segurança)
domfinder -d exemplo.com -o all_subs.txt -VT SUA_API_KEY

# mantendo os arquivos individuais de cada fonte (crtsh.txt, subfinder.txt, etc)
domfinder -d exemplo.com -o /Documentos/recon/all_subs.txt -vv
```

## Saída

O arquivo indicado em `-o` contém a lista final de subdomínios únicos, um por linha, ordenados alfabeticamente.

Com `-vv`, os arquivos brutos de cada fonte também ficam disponíveis no mesmo diretório:

```
/Documentos/recon/
├── crtsh.txt
├── subfinder.txt
├── assetfinder.txt
├── amass.txt
├── vt.txt
└── all_subs.txt   <- resultado final consolidado
```

## Resiliência

- Se o **crt.sh** não responder com JSON válido (rate limit é comum), o script tenta novamente algumas vezes com backoff antes de pular essa fonte, sem interromper a execução.
- O mesmo vale para o **VirusTotal** em caso de key inválida ou limite de requisições excedido.
- Nenhuma falha de fonte individual derruba o script — ele sempre gera o consolidado com o que conseguiu coletar.

## Aviso legal

Esta ferramenta realiza apenas coleta **passiva** de informação, a partir de fontes públicas. Ainda assim, use somente em domínios para os quais você tem autorização explícita — programas de bug bounty com escopo definido, pentests contratados, ou ativos próprios. O uso indevido é de responsabilidade exclusiva de quem executa a ferramenta.

## Autor

**jbug0x**

## Licença

MIT
