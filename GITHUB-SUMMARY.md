# 🚀 ZshMap v0.1.0 — Primeira release

Texto pronto para colar nas **Release notes** ou na descrição do repositório no GitHub.

---

## 🚀 ZshMap v0.1.0 — Primeira release

Bem-vindo à primeira versão do ZshMap! 🎉

O projeto nasce com a proposta de transformar ficheiros **YAML** em **menus dinâmicos no terminal (Whiptail)**, geração de **`~/.zprofile-auto`** com **funções Zsh** por atalho (mais aliases fixos no cabeçalho gerado) e fluxos reutilizáveis para acelerar o dia a dia no shell.

### ✨ O que já está disponível

- 📂 Leitura automática de **`zshmap.yml`** na raiz de cada projeto (sob o diretório configurado em `~/.zshmap.yml` → `projects.dir`).
- 🏠 Suporte a **`~/.zshmap.yml`** na home (exemplo no repositório: `.zshmap.home.example.yml`).
- 🔄 Fallback legado para **`workerboss.yml`** quando `zshmap.yml` ainda não existir nessa pasta.
- 🧭 Menus dinâmicos com **Whiptail** (inclui gauge em execuções longas, conforme o fluxo do atalho).
- ⚡ Geração automática de **`~/.zprofile-auto`** (e symlink sugerido em `~/.zprofile-auto` apontando para o ficheiro no clone do repositório, conforme o script).
- 🔗 Atalhos em **`project.shortcuts`** viram **funções Zsh** com o mesmo nome do atalho após `source ~/.zprofile-auto`.
- 🛠️ Integração com fluxos **Git** e informações de sistema no menu principal.
- 📜 **`shell.extras_source`** em `~/.zshmap.yml` para fazer `source` de ficheiros `.zsh` extra.
- 📦 Instalação opcional de **scripts `.sh`** em pastas listadas em `install.programs_dir` (requer **yq**).

### ⌨️ Comandos reais (clone típico)

```bash
git clone git@github.com:CeruttiMaicon/zsh-map.git
cd zsh-map
chmod +x zsh-map.sh install_whiptail.sh

# Dependência de UI no terminal
./install_whiptail.sh

# Smoke test opcional do Whiptail (não usa ~/.zshmap.yml)
./test_whiptail.sh

# Menu principal
./zsh-map.sh
```

### 🏠 Configuração global

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

No menu do ZshMap: **Gerar .zprofile-auto**. Depois num terminal Zsh (ou abre um terminal novo, conforme o fluxo do script):

```bash
source ~/.zprofile-auto
```

### 🧱 Histórico desta versão — v0.1.0

- ✨ Publicação inicial do projeto.
- ♻️ Migração de `workerboss.yml` para **`zshmap.yml`** (com fallback legado).
- 📖 Documentação no README e neste ficheiro para releases.
- 🚀 Estrutura inicial do sistema de atalhos dinâmicos por projeto.

### 💡 Sobre o projeto

O **ZshMap** é um menu em terminal baseado em **Whiptail** que centraliza atalhos, comandos e fluxos definidos em YAML, permitindo ambientes de desenvolvimento mais rápidos e padronizados entre repositórios.

### 🔥 Exemplo real de ideia (`zshmap.yml` na raiz do projeto)

O schema esperado é **`project`** com **`shortcuts`** (lista). Cada atalho tem pelo menos **`name`**, **`type`**, **`path`** (relativo à raiz do repo) e **`command`** *ou* lista **`commands`**.

⬇️ Depois de gerares o `.zprofile-auto` e fazeres `source ~/.zprofile-auto`, podes chamar **`up`** e **`test`** como funções no Zsh (no diretório do projeto o `path` é aplicado ao `cd` interno da função gerada).

```yaml
project:
  name: "Meu projeto"
  shortcuts:
    - name: up
      title: "Subir stack (Docker)"
      type: test
      path: "."
      command: docker compose up -d

    - name: test
      title: "Testes Artisan"
      type: test
      path: "."
      command: php artisan test
```

**Nota:** `type: test` é um dos tipos “normais” tratados pelo script (comandos diretos após `setup_shortcut`, se existir). Existem também tipos especiais como `helper`, `parameterized`, `dump` e `interactive-test` — vê a lógica em `zsh-map.sh` para casos avançados.

### ✅ Requisitos rápidos

- Ubuntu/Debian (ou compatível), **Bash 4+**, **Whiptail**, **yq** para YAML global e por projeto.
