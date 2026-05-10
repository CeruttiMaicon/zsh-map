# ZshMap

Ferramenta com menu **Whiptail** que lê **`zshmap.yml`** na raiz de cada projeto (com fallback legado para `workerboss.yml`) e **`~/.zshmap.yml`** na home, gera **`~/.zprofile-auto`** e integra extras Zsh, Git, instalação opcional de programas (pastas configuradas em lista) e mais.

Repositório: **`zsh-map`** (clone típico `~/Projects/zsh-map`).

## ✨ Novidades

**Interface no terminal com Whiptail**

O ZshMap oferece:
- Menus e confirmações no terminal
- Barras de progresso em operações longas
- Navegação por teclado
- **Fluxos em etapas:** telas Whiptail encadeadas guiam a escolha do projeto, do atalho e das confirmações, para não teres de decorar comandos longos no dia a dia.

## 🚀 Como usar

### Instalação das dependências
```bash
./install_whiptail.sh
```

### Teste rápido do Whiptail (opcional)
O **`test_whiptail.sh`** na raiz abre uma `msgbox` e um `menu` mínimos — não usa `~/.zshmap.yml`.

```bash
./test_whiptail.sh
```

### Execução principal
```bash
./zsh-map.sh
```

## Configuração global

1. **Recomendado:** no menu, **Configurar ~/.zshmap.yml (start)**. O script cria `~/.zshmap.yml` a partir de `.zshmap.home.example.yml` (no mesmo diretório que `zsh-map.sh`) se ainda não existir; mostra Git (nome, email, editor) e abre o ficheiro no editor.

   Alternativa manual:
```bash
touch ~/.zshmap.yml
```

   **Migração:** se ainda tiveres só `~/.workerboss.yml`, copia ou renomeia para **`~/.zshmap.yml`** (o ZshMap já não lê o nome antigo).

2. Exemplo de `~/.zshmap.yml`:
```yaml
projects:
  dir: "~/Projects"
  ignore_dirs:
    - "project-1"
    - "project-2"

install:
  programs_dir:
    - "~/Projects/substitui-pelo-repo/programs"
    - "~/Projects/substitui-pelo-repo/outros-programs"

shell:
  extras_source:
    - "~/Projects/substitui-pelo-repo/.zshmap-extras.zsh"
```

3. **Extras Zsh:** ficheiros ocultos `.zsh` listados em `shell.extras_source` (lista).

4. No ZshMap: **Gerar .zprofile-auto**. Abre um terminal novo ou `source ~/.zprofile-auto`.

## Funcionalidades

### Instalação de programas
- `install.programs_dir` é **sempre uma lista** em `~/.zshmap.yml`; requer **yq**. O menu só aparece se alguma pasta listada existir e tiver `.sh`.

### Atalhos dinâmicos e integração com o Zsh
- **Criação dinâmica por projeto:** cada repositório pode declarar atalhos no seu `zshmap.yml` (na raiz); o ZshMap descobre projetos a partir de `~/.zshmap.yml` e monta menus e ações em função do que está definido — não precisas de editar o script para cada novo projeto ou comando.
- **Por projeto:** `zshmap.yml` na raiz do repo; `workerboss.yml` ainda é aceite se o novo nome ainda não existir.
- **Global:** `~/.zshmap.yml` — `projects`, `install`, `shell.extras_source`.
- **Whiptail como “assistente”:** as integrações de telas (menus, listas, caixas de mensagem) encaixam-se no fluxo de execução dos atalhos — escolhes o contexto no menu e segues as etapas até correr o que precisas, com menos erros e menos cópia de comandos.
- **Aliases no Zsh:** ao gerares **`~/.zprofile-auto`** e o carregares no teu shell, os atalhos ficam também expostos como **aliases Zsh**, para invocares os mesmos fluxos (ou comandos gerados) direto na linha de comandos, além do menu Whiptail.

### Git, Zsh, sistema
- Configuração Git local, dependências Zsh, informações do sistema (conforme opções do menu).

## Requisitos

- Ubuntu/Debian (ou compatível)
- Bash 4+
- Whiptail
- **yq** para YAML global e projetos

## Estrutura do repositório

```
zsh-map/
├── zsh-map.sh            # Interface principal ⭐
├── install_whiptail.sh
├── programs/             # README sobre install.programs_dir
├── git/
├── zsh/
├── programs.sh
├── zsh-dependencies.sh
└── README.md
```

## Primeiros passos

```bash
git clone git@github.com:CeruttiMaicon/zsh-map.git
cd zsh-map
./install_whiptail.sh
./zsh-map.sh
```

(Ajusta a URL do clone à tua organização/conta.)

## Permissões

```bash
chmod +x zsh-map.sh
chmod +x install_whiptail.sh
```

## Licença

MIT.

---

**ZshMap** — YAML, menu e Zsh no mesmo fluxo.
