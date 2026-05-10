#!/bin/bash

# ZshMap - Interface Gráfica com Whiptail
# Sistema de Automação para Desenvolvedores

# Cores para o terminal (fallback)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variáveis globais para cache de senha
CACHED_SUDO_PASSWORD=""
SUDO_PASSWORD_VALID=false
SUDO_TIMESTAMP=0
SUDO_TIMEOUT=300  # 5 minutos de timeout
SUDO_CACHE_FILE="/tmp/zshmap_sudo_cache_$$"
# Variável global para cache de tenant_name entre dump e dump-qa
GLOBAL_TENANT_NAME=""

# YAML global na home (ficheiro oculto)
_zshmap_home_config_path() {
    printf '%s' "$HOME/.zshmap.yml"
}

_zshmap_is_home_main_config() {
    [ "$1" = "$HOME/.zshmap.yml" ]
}

# Função para verificar se whiptail está instalado
check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "❌ Whiptail não está instalado. Instale manualmente com: sudo apt install whiptail"
                exit 1
    fi
}

# Função para verificar se yq está instalado
check_yq() {
    if ! command -v yq &> /dev/null; then
        # Solicitar senha do sudo se necessário
        local sudo_password=""
        if [ "$EUID" -ne 0 ]; then
            sudo_password=$(get_sudo_password)
            if [ $? -ne 0 ]; then
                whiptail --title "❌ Erro" \
                         --msgbox "yq não está instalado e não foi possível obter permissões para instalá-lo.\n\nInstale manualmente com: sudo apt install yq" \
                         10 60
                return 1
            fi
        fi
        
        # Instalar yq
        if [ -n "$sudo_password" ]; then
            echo "$sudo_password" | sudo -S apt update && echo "$sudo_password" | sudo -S apt install -y yq
        else
            apt update && apt install -y yq
        fi
        
        # Verificar se a instalação foi bem-sucedida
        if ! command -v yq &> /dev/null; then
            whiptail --title "❌ Erro" \
                     --msgbox "Falha ao instalar yq!\n\nInstale manualmente com: sudo apt install yq" \
                     10 60
            return 1
        fi
    fi
    return 0
}

# Função para verificar se a senha em cache ainda é válida
is_sudo_password_valid() {
    # Verificar se o arquivo de cache existe
    if [ ! -f "$SUDO_CACHE_FILE" ]; then
        return 1
    fi
    
    # Ler dados do cache
    local cache_data=$(cat "$SUDO_CACHE_FILE" 2>/dev/null)
    if [ -z "$cache_data" ]; then
        return 1
    fi
    
    # Extrair timestamp e senha
    local cached_timestamp=$(echo "$cache_data" | cut -d'|' -f1)
    local cached_password=$(echo "$cache_data" | cut -d'|' -f2-)
    
    # Verificar se o timestamp é válido
    if [ -z "$cached_timestamp" ] || [ -z "$cached_password" ]; then
        clear_sudo_password_cache
        return 1
    fi
    
    local current_time=$(date +%s)
    local time_diff=$((current_time - cached_timestamp))
    
    # Verificar se não expirou
    if [ $time_diff -ge $SUDO_TIMEOUT ]; then
        clear_sudo_password_cache
        return 1
    fi
    
    # Testar se a senha ainda funciona
    if echo "$cached_password" | sudo -S true 2>/dev/null; then
        # Atualizar variáveis globais para compatibilidade
        CACHED_SUDO_PASSWORD="$cached_password"
        SUDO_PASSWORD_VALID=true
        SUDO_TIMESTAMP="$cached_timestamp"
        return 0
    else
        # Senha não funciona mais, limpar cache
        clear_sudo_password_cache
        return 1
    fi
}

# Função para limpar o cache de senha
clear_sudo_password_cache() {
    CACHED_SUDO_PASSWORD=""
    SUDO_PASSWORD_VALID=false
    SUDO_TIMESTAMP=0
    rm -f "$SUDO_CACHE_FILE" 2>/dev/null
}

# Função para armazenar senha no cache
cache_sudo_password() {
    local password="$1"
    local timestamp=$(date +%s)
    
    # Armazenar no arquivo temporário
    echo "${timestamp}|${password}" > "$SUDO_CACHE_FILE" 2>/dev/null
    
    # Atualizar variáveis globais para compatibilidade
    CACHED_SUDO_PASSWORD="$password"
    SUDO_PASSWORD_VALID=true
    SUDO_TIMESTAMP="$timestamp"
}

# Função para obter senha do sudo (com cache)
get_sudo_password() {
    # Debug: verificar estado do cache
    # echo "DEBUG: SUDO_PASSWORD_VALID=$SUDO_PASSWORD_VALID" >&2
    # echo "DEBUG: CACHED_SUDO_PASSWORD length=${#CACHED_SUDO_PASSWORD}" >&2
    # echo "DEBUG: SUDO_TIMESTAMP=$SUDO_TIMESTAMP" >&2
    
    # Verificar se já temos uma senha válida em cache
    if is_sudo_password_valid; then
        # Usar senha em cache silenciosamente
        echo "$CACHED_SUDO_PASSWORD"
        return 0
    fi
    
    # Solicitar nova senha
    local password=$(request_sudo_password)
    if [ $? -eq 0 ]; then
        # Armazenar no cache
        cache_sudo_password "$password"
        echo "$password"
        return 0
    fi
    
    return 1
}

# Função para solicitar senha do sudo de forma elegante
request_sudo_password() {
    local password=""
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Solicitar senha com interface elegante
        password=$(whiptail --title "🔐 Autenticação Necessária" \
                           --passwordbox "Para continuar com a instalação, é necessário autenticação administrativa.\n\nDigite sua senha do sudo:" \
                           12 60 \
                           3>&1 1>&2 2>&3)
        
        # Verificar se o usuário cancelou
        if [ $? -ne 0 ]; then
            whiptail --title "❌ Cancelado" \
                     --msgbox "Operação cancelada pelo usuário.\n\nA instalação não pode continuar sem autenticação." \
                     8 60
            return 1
        fi
        
        # Verificar se a senha está vazia
        if [ -z "$password" ]; then
            whiptail --title "⚠️  Senha Vazia" \
                     --msgbox "A senha não pode estar vazia!\n\nTentativa $attempt de $max_attempts" \
                     8 60
            ((attempt++))
            continue
        fi
        
        # Testar a senha
        if echo "$password" | sudo -S true 2>/dev/null; then
            # Senha válida
            echo "$password"
            return 0
        else
            # Senha inválida
            if [ $attempt -lt $max_attempts ]; then
                whiptail --title "❌ Senha Incorreta" \
                         --msgbox "Senha incorreta!\n\nTentativa $attempt de $max_attempts\n\nTente novamente." \
                         8 60
            else
                whiptail --title "❌ Máximo de Tentativas" \
                         --msgbox "Máximo de tentativas excedido!\n\nA instalação não pode continuar." \
                         8 60
                return 1
            fi
            ((attempt++))
        fi
    done
    
    return 1
}

# Função para executar comando com sudo usando senha armazenada
execute_with_sudo() {
    local password="$1"
    local command="$2"
    
    # Executar comando usando a senha fornecida
    echo "$password" | sudo -S bash -c "$command" 2>/dev/null
    return $?
}

# Função para listar diretórios (equivalente ao listDirectories do Python)
list_directories() {
    local directory="$1"
    
    if [ ! -d "$directory" ]; then
        return 1
    fi
    
    # Listar diretórios, excluindo arquivos especiais e o diretório pai
    find "$directory" -maxdepth 1 -type d -printf "%f\n" | \
    grep -v "^\.$" | \
    grep -v "^programs$" | \
    grep -v "__pycache__" | \
    grep -v "programs.py" | \
    sort
}

# Função para listar scripts em um diretório específico
list_scripts() {
    local directory="$1"
    
    if [ ! -d "$directory" ]; then
        return 1
    fi
    
    # Listar apenas arquivos .sh, excluindo diretórios
    find "$directory" -maxdepth 1 -type f -name "*.sh" | \
    sed 's|.*/||' | \
    sort
}

# Emite paths (ainda com ~) a partir de install.programs_dir — tem de ser **lista** no YAML (yq).
_zshmap_programs_dirs_emit_configured_raw() {
    local main_config typ
    main_config="$(_zshmap_home_config_path)"
    [ -f "$main_config" ] && command -v yq &>/dev/null || return 0
    typ=$(yq -r '.install.programs_dir | type' "$main_config" 2>/dev/null || echo "")
    case "$typ" in
        array|!!seq)
            yq -r '.install.programs_dir[]' "$main_config" 2>/dev/null
            ;;
        *)
            ;;
    esac
}

# Uma linha por path, ~ expandido, sem linhas vazias.
_zshmap_programs_dirs_emit_expanded() {
    local line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ "$line" = "null" ] && continue
        printf '%s\n' "${line/#\~/$HOME}"
    done < <(_zshmap_programs_dirs_emit_configured_raw)
}

# Pastas distintas que existem e têm pelo menos um .sh (para menu e escolha).
_zshmap_programs_emit_roots_with_scripts() {
    local dir f
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        [ -d "$dir" ] || continue
        f=$(find "$dir" -type f -name '*.sh' -print -quit 2>/dev/null)
        [ -n "$f" ] && printf '%s\n' "$dir"
    done < <(_zshmap_programs_dirs_emit_expanded) | sort -u
}

# True se alguma pasta configurada tiver scripts .sh.
_zshmap_programs_has_any_sh() {
    _zshmap_programs_emit_roots_with_scripts | grep -q .
}

# Escolhe uma pasta base (stdout) quando há várias com scripts; com uma só, devolve essa.
_zshmap_programs_choose_root_interactive() {
    local -a roots=()
    local r n i disp choice mh
    while IFS= read -r r; do
        [ -n "$r" ] && roots+=("$r")
    done < <(_zshmap_programs_emit_roots_with_scripts)
    n=${#roots[@]}
    if [ "$n" -eq 0 ]; then
        return 1
    fi
    if [ "$n" -eq 1 ]; then
        printf '%s\n' "${roots[0]}"
        return 0
    fi
    local -a menu=()
    for ((i=0; i<n; i++)); do
        disp="${roots[$i]}"
        if [ ${#disp} -gt 60 ]; then
            disp="...${disp: -57}"
        fi
        menu+=("$i" "$disp")
    done
    mh=$n
    [ "$mh" -gt 12 ] && mh=12
    choice=$(whiptail --title "📂 Pastas de instalação" \
                      --menu "Várias entradas em install.programs_dir. Escolhe a pasta para listar SO e scripts .sh:" \
                      $((mh + 8)) 72 "$mh" \
                      "${menu[@]}" \
                      3>&1 1>&2 2>&3) || return 1
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -ge "$n" ]; then
        return 1
    fi
    printf '%s\n' "${roots[$choice]}"
    return 0
}

# Função para verificar se o arquivo YAML existe e é válido
validate_yaml_file() {
    local yaml_file="${1:-$(_zshmap_home_config_path)}"
    
    if [ ! -f "$yaml_file" ]; then
        if _zshmap_is_home_main_config "$yaml_file"; then
            whiptail --title "❌ Arquivo não encontrado" \
                     --msgbox "Arquivo de configuração global não encontrado.\n\nCrie ~/.zshmap.yml na sua home.\n\nExemplo: .zshmap.home.example.yml no repositório zsh-map." \
                     12 62
        fi
        return 1
    fi
    
    # Verificar se o arquivo YAML é válido
    if _zshmap_is_home_main_config "$yaml_file"; then
        # Para arquivo principal, verificar se tem .projects.dir
        if ! yq '.projects.dir' "$yaml_file" >/dev/null 2>&1; then
            whiptail --title "❌ Arquivo YAML inválido" \
                     --msgbox "O arquivo $yaml_file contém YAML inválido!\n\nVerifique a sintaxe do arquivo." \
                     10 60
            return 1
        fi
    else
        # Para arquivos de projeto, verificar se tem .project
        if ! yq '.project' "$yaml_file" >/dev/null 2>&1; then
            whiptail --title "❌ Arquivo YAML inválido" \
                     --msgbox "O arquivo $yaml_file contém YAML inválido!\n\nVerifique a sintaxe do arquivo." \
                     10 60
        return 1
        fi
    fi
    
    return 0
}

# Caminho do YAML de atalhos dentro da pasta do repositório (prefere zshmap.yml; aceita workerboss.yml legado).
_zshmap_resolve_yaml_in_project_dir() {
    local d="${1%/}"
    [ -n "$d" ] || return 1
    if [ -f "$d/zshmap.yml" ]; then
        printf '%s\n' "$d/zshmap.yml"
        return 0
    fi
    if [ -f "$d/workerboss.yml" ]; then
        printf '%s\n' "$d/workerboss.yml"
        return 0
    fi
    return 1
}

# Lista zshmap.yml (ou workerboss.yml legado) por projeto sob projects.dir, excluindo pastas em projects.ignore_dirs
# do arquivo ~/.zshmap.yml. Uma entrada por pasta de repositório; saída null-terminated (-print0).
find_zshmap_project_yamls() {
    local projects_dir="$1"
    local main_config="${2:-$(_zshmap_home_config_path)}"
    local shopt_restore
    shopt_restore=$(shopt -p nullglob 2>/dev/null || true)
    shopt -s nullglob

    local d project_dir_name yaml_path skip len idx ign
    for d in "$projects_dir"/*/; do
        [ -d "$d" ] || continue
        project_dir_name=$(basename "${d%/}")
        skip=false
        if [ -f "$main_config" ]; then
            len=$(yq '.projects.ignore_dirs // [] | length' "$main_config" 2>/dev/null)
            if [ -n "$len" ] && [ "$len" != "null" ] && [ "$len" != "0" ]; then
                idx=0
                while [ "$idx" -lt "$len" ]; do
                    ign=$(yq -r ".projects.ignore_dirs[$idx] // \"\"" "$main_config" 2>/dev/null)
                    if [ -n "$ign" ] && [ "$ign" != "null" ]; then
                        ign="${ign%/}"
                        ign="${ign##*/}"
                        if [ "$project_dir_name" = "$ign" ]; then
                            skip=true
                            break
                        fi
                    fi
                    idx=$((idx + 1))
                done
            fi
        fi
        [ "$skip" = true ] && continue

        yaml_path=""
        yaml_path=$(_zshmap_resolve_yaml_in_project_dir "$d") || true
        if [ -n "$yaml_path" ]; then
            printf '%s\0' "$yaml_path"
        fi
    done

    if [ -n "$shopt_restore" ]; then
        eval "$shopt_restore" 2>/dev/null || true
    fi
}

# Função para detectar projetos dinamicamente
detect_projects() {
    local projects_dir=""
    local projects=()
    local count=0
    
    # Obter diretório de projetos do arquivo de configuração principal
    local main_config="$(_zshmap_home_config_path)"
    if [ -f "$main_config" ]; then
        projects_dir=$(yq -r ".projects.dir" "$main_config" 2>/dev/null)
        # Expandir ~ para home directory
        projects_dir="${projects_dir/#\~/$HOME}"
    else
        # Fallback para diretório padrão
        projects_dir="$HOME/Projects"
    fi
    
    # Verificar se o diretório Projects existe
    if [ ! -d "$projects_dir" ]; then
        whiptail --title "❌ Diretório não encontrado" \
                 --msgbox "Diretório $projects_dir não encontrado!\n\nCrie o diretório e adicione seus projetos." \
                 10 60
        return 1
    fi
    
    # Buscar por zshmap.yml (ou workerboss.yml legado) em cada pasta de projeto
    while IFS= read -r -d '' project_path; do
        local project_dir=$(basename "$(dirname "$project_path")")
        
        # Pular o próprio repositório zsh-map (ou clone antigo worker-boss)
        if [ "$project_dir" = "zsh-map" ] || [ "$project_dir" = "worker-boss" ]; then
            continue
        fi
        
        # Verificar se o arquivo YAML é válido
        if validate_yaml_file "$project_path"; then
            # Menu: nome lógico do YAML (project.name); fallback = pasta do repositório
            local display_name
            display_name=$(yq -r '.project.name // ""' "$project_path" 2>/dev/null)
            if [ -z "$display_name" ] || [ "$display_name" = "null" ]; then
                display_name="$project_dir"
            fi
            projects+=("$count" "$display_name")
            ((count++))
        fi
    done < <(find_zshmap_project_yamls "$projects_dir")
    
    if [ ${#projects[@]} -eq 0 ]; then
        whiptail --title "❌ Nenhum projeto encontrado" \
                 --msgbox "Nenhum projeto com zshmap.yml (ou workerboss.yml legado) encontrado em $projects_dir!\n\nAdicione zshmap.yml na raiz de cada projeto." \
                 10 60
        return 1
    fi
    
    # Verificar atalhos duplicados (apenas informativo, não bloqueia)
    # validate_duplicate_shortcuts
    
    # Mostrar menu de seleção de projetos
    local choice=$(whiptail --title "📁 Selecionar Projeto" \
                           --menu "Escolha um projeto:" \
                           20 60 12 \
                           "${projects[@]}" \
                           3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$choice" ] && [[ "$choice" =~ ^[0-9]+$ ]]; then
        # Encontrar o nome do projeto correspondente ao índice
        local project_name=""
        local count=0
        while IFS= read -r -d '' project_path; do
            local current_project=$(basename "$(dirname "$project_path")")
            
            # Pular o próprio repositório zsh-map (ou clone antigo worker-boss)
            if [ "$current_project" = "zsh-map" ] || [ "$current_project" = "worker-boss" ]; then
                continue
            fi
            
            # Mesma ordem e filtro do loop que monta o menu (índice = pasta do projeto)
            if ! validate_yaml_file "$project_path"; then
                continue
            fi
            
            if [ "$count" -eq "$choice" ]; then
                project_name="$current_project"
                break
            fi
            ((count++))
        done < <(find_zshmap_project_yamls "$projects_dir")
        
        
        echo "$project_name"
    else
        return 1
    fi
}

# Função para obter o caminho do zshmap.yml (ou workerboss.yml legado) de um projeto
get_project_yaml_path() {
    local project_name="$1"
    local projects_dir=""
    
    # Obter diretório de projetos do arquivo de configuração principal
    local main_config="$(_zshmap_home_config_path)"
    if [ -f "$main_config" ]; then
        projects_dir=$(yq -r ".projects.dir" "$main_config" 2>/dev/null)
        # Expandir ~ para home directory
        projects_dir="${projects_dir/#\~/$HOME}"
    else
        # Fallback para diretório padrão
        projects_dir="$HOME/Projects"
    fi
    
    local yaml_path=""
    yaml_path=$(_zshmap_resolve_yaml_in_project_dir "$projects_dir/$project_name") || return 1
    printf '%s\n' "$yaml_path"
    return 0
}

# Função para verificar atalhos duplicados entre projetos (informativa)
validate_duplicate_shortcuts() {
    local projects_dir=""
    local all_shortcuts=()
    local duplicates=()
    local project_shortcuts=()
    
    # Obter diretório de projetos do arquivo de configuração principal
    local main_config="$(_zshmap_home_config_path)"
    if [ -f "$main_config" ]; then
        projects_dir=$(yq -r ".projects.dir" "$main_config" 2>/dev/null)
        # Expandir ~ para home directory
        projects_dir="${projects_dir/#\~/$HOME}"
    else
        # Fallback para diretório padrão
        projects_dir="$HOME/Projects"
    fi
    
    # Coletar todos os atalhos de todos os projetos
    while IFS= read -r -d '' yaml_path; do
        local project_name=$(basename "$(dirname "$yaml_path")")
        
        # Pular o próprio repositório zsh-map (ou clone antigo worker-boss)
        if [ "$project_name" = "zsh-map" ] || [ "$project_name" = "worker-boss" ]; then
            continue
        fi
        
        # Verificar se o arquivo YAML é válido
        if validate_yaml_file "$yaml_path"; then
            # Extrair atalhos do projeto
            local shortcuts=$(yq -r ".project.shortcuts[] | .name" "$yaml_path" 2>/dev/null)
            
            while IFS= read -r shortcut_name; do
                if [ -n "$shortcut_name" ]; then
                    # Verificar se já existe
                    local found=false
                    for existing in "${all_shortcuts[@]}"; do
                        if [ "$existing" = "$shortcut_name" ]; then
                            found=true
                            # Adicionar à lista de duplicatas se não estiver já
                            local already_duplicate=false
                            for dup in "${duplicates[@]}"; do
                                if [ "$dup" = "$shortcut_name" ]; then
                                    already_duplicate=true
                                    break
                                fi
                            done
                            if [ "$already_duplicate" = false ]; then
                                duplicates+=("$shortcut_name")
                            fi
                            break
                        fi
                    done
                    
                    if [ "$found" = false ]; then
                        all_shortcuts+=("$shortcut_name")
                    fi
                    
                    # Armazenar relação projeto-atalho
                    project_shortcuts+=("$project_name:$shortcut_name")
                fi
            done <<< "$shortcuts"
        fi
    done < <(find_zshmap_project_yamls "$projects_dir")
    
    # Mostrar resultado (informativo)
    # Retorno: 1 = existem duplicados, 0 = nenhum duplicado
    if [ ${#duplicates[@]} -gt 0 ]; then
        echo ""
        echo "⚠️  ATENÇÃO: Atalhos duplicados encontrados:"
        for duplicate in "${duplicates[@]}"; do
            echo "  🔴 $duplicate encontrado em:"
            for project_shortcut in "${project_shortcuts[@]}"; do
                local project=$(echo "$project_shortcut" | cut -d':' -f1)
                local shortcut=$(echo "$project_shortcut" | cut -d':' -f2)
                if [ "$shortcut" = "$duplicate" ]; then
                    echo "    - $project"
                fi
            done
        done
        echo ""
        return 1
    else
        echo "✅ Nenhum atalho duplicado encontrado!"
        return 0
    fi
}

# Função para listar projetos do arquivo YAML
list_yaml_projects() {
    local yaml_file=""
    if [ -f "./zshmap.yml" ]; then
        yaml_file="./zshmap.yml"
    elif [ -f "./workerboss.yml" ]; then
        yaml_file="./workerboss.yml"
    else
        yaml_file="./zshmap.yml"
    fi
    local projects=()
    local count=0
    
    # Verificar se o arquivo é válido
    if ! validate_yaml_file; then
        return 1
    fi
    
    # Listar projetos usando yq
    while IFS= read -r project; do
        if [ -n "$project" ]; then
            projects+=("$count" "$project")
            ((count++))
        fi
    done < <(yq -r '.projects | keys[]' "$yaml_file" 2>/dev/null)
    
    if [ ${#projects[@]} -eq 0 ]; then
        whiptail --title "❌ Nenhum projeto encontrado" \
                 --msgbox "Nenhum projeto encontrado no arquivo $yaml_file!\n\nVerifique se o arquivo contém projetos configurados." \
                 10 60
        return 1
    fi
    
    # Mostrar menu de seleção de projetos
    local choice=$(whiptail --title "📁 Selecionar Projeto" \
                           --menu "Escolha um projeto:" \
                           20 60 10 \
                           "${projects[@]}" \
                           3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$choice" ] && [[ "$choice" =~ ^[0-9]+$ ]]; then
        # Obter nome do projeto selecionado
        local project_name=""
        local count=0
        while IFS= read -r project; do
            if [ -n "$project" ]; then
                if [ "$count" -eq "$choice" ]; then
                    project_name="$project"
                    break
                fi
                ((count++))
            fi
        done < <(yq -r '.projects | keys[]' "$yaml_file" 2>/dev/null)
        
        echo "$project_name"
    else
        return 1
    fi
}

# Função para listar atalhos de um projeto específico
list_project_shortcuts() {
    local project_name="$1"
    local yaml_file=""
    local shortcuts=()
    local count=0
    
    
    # Obter o caminho do arquivo YAML do projeto
    yaml_file=$(get_project_yaml_path "$project_name")
    if [ $? -ne 0 ] || [ -z "$yaml_file" ]; then
        whiptail --title "❌ Arquivo não encontrado" \
                 --msgbox "Arquivo zshmap.yml (ou workerboss.yml legado) não encontrado para o projeto $project_name!" \
                 10 60
        return 1
    fi
    
    # Verificar se o arquivo é válido
    if ! validate_yaml_file "$yaml_file"; then
        return 1
    fi
    
    # Listar atalhos do projeto usando yq
    while IFS= read -r shortcut; do
        if [ -n "$shortcut" ]; then
            # Extrair nome e tipo do atalho
            local shortcut_name=$(echo "$shortcut" | cut -d'|' -f1)
            local shortcut_type=$(echo "$shortcut" | cut -d'|' -f2)
            shortcuts+=("$count" "$shortcut_name ($shortcut_type)")
            ((count++))
        fi
    done < <(yq -r ".project.shortcuts[] | .name + \"|\" + .type" "$yaml_file" 2>/dev/null)
    
    if [ ${#shortcuts[@]} -eq 0 ]; then
        whiptail --title "❌ Nenhum atalho encontrado" \
                 --msgbox "Nenhum atalho encontrado para o projeto $project_name!\n\nVerifique se o projeto tem atalhos configurados." \
                 10 60
        return 1
    fi
    
    # Mostrar menu de seleção de atalhos
    local choice=$(whiptail --title "⚡ Selecionar Atalho - $project_name" \
                           --menu "Escolha um atalho:" \
                           20 60 12 \
                           "${shortcuts[@]}" \
                           3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$choice" ] && [[ "$choice" =~ ^[0-9]+$ ]]; then
        # Obter detalhes do atalho selecionado
        local shortcut_name=""
        local shortcut_path=""
        local shortcut_command=""
        local count=0
        
        while IFS= read -r shortcut_data; do
            if [ -n "$shortcut_data" ]; then
                if [ "$count" -eq "$choice" ]; then
                    shortcut_name=$(echo "$shortcut_data" | cut -d'|' -f1)
                    shortcut_path=$(echo "$shortcut_data" | cut -d'|' -f2)
                    shortcut_command=$(echo "$shortcut_data" | cut -d'|' -f3)
                    break
                fi
                ((count++))
            fi
        done < <(yq -r ".project.shortcuts[] | .name + \"|\" + .path + \"|\" + .command" "$yaml_file" 2>/dev/null)
        
        # Retornar dados do atalho
        echo "$shortcut_name|$shortcut_path|$shortcut_command"
    else
        return 1
    fi
}

# Função para executar atalho selecionado
execute_shortcut() {
    local project_name="$1"
    local shortcut_name="$2"
    local shortcut_path="$3"
    local shortcut_command="$4"
    
    # Obter o caminho do arquivo YAML do projeto
    local yaml_file=$(get_project_yaml_path "$project_name")
    if [ $? -ne 0 ] || [ -z "$yaml_file" ]; then
        whiptail --title "❌ Erro" \
                 --msgbox "Arquivo zshmap.yml (ou workerboss.yml legado) não encontrado para o projeto $project_name!" \
                 10 60
        return 1
    fi
    
    # Verificar se o arquivo YAML existe e é válido
    if [ ! -f "$yaml_file" ]; then
        whiptail --title "❌ Erro" \
                 --msgbox "Arquivo $yaml_file não encontrado!" \
                 10 60
        return 1
    fi
    
    # Obter diretório raiz do projeto
    local project_root=$(yq -r ".project.root" "$yaml_file" 2>/dev/null)
    
    if [ -z "$project_root" ] || [ "$project_root" = "null" ]; then
        whiptail --title "❌ Erro" \
                 --msgbox "Não foi possível obter o diretório raiz do projeto '$project_name'!\n\nVerifique se o projeto existe no arquivo $yaml_file" \
                 12 60
        return 1
    fi
    
    # Expandir ~ no caminho
    project_root="${project_root/#\~/$HOME}"
    
    # Verificar e clonar repositório se necessário
    local github_url=$(yq -r ".project.github" "$yaml_file" 2>/dev/null)
    if [ -n "$github_url" ] && [ "$github_url" != "null" ]; then
        # Verificar se o diretório do projeto existe
        if [ ! -d "$project_root" ]; then
            echo "📦 Projeto $project_name não encontrado. Clonando repositório..."
            clone_repo "$project_root" "$github_url" "$project_name"
            if [ $? -ne 0 ]; then
                whiptail --title "❌ Erro" \
                         --msgbox "Falha ao clonar o repositório $github_url!\n\nVerifique sua conexão e permissões de Git." \
                         12 60
                return 1
            fi
        else
            echo "✅ Projeto $project_name já existe. Continuando..."
        fi
    fi
    
    # Construir caminho completo
    local full_path="$project_root/$shortcut_path"
    
    # Verificar se o diretório existe
    if [ ! -d "$full_path" ]; then
        whiptail --title "❌ Diretório não encontrado" \
                 --msgbox "Diretório não encontrado: $full_path\n\nVerifique se o caminho está correto no arquivo de configuração." \
                 12 60
        return 1
    fi
    
    # Verificar se tem setup_shortcut
    local setup_shortcut=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .setup_shortcut" "$yaml_file" 2>/dev/null)
    if [ "$setup_shortcut" != "null" ] && [ -n "$setup_shortcut" ]; then
        echo "🔧 Executando comando de preparação: $setup_shortcut"
        execute_shortcut "$project_name" "$setup_shortcut"
        if [ $? -ne 0 ]; then
            whiptail --title "❌ Erro" \
                     --msgbox "Falha ao executar comando de preparação: $setup_shortcut" \
                     8 60
            return 1
        fi
    fi
    
    # Verificar se é comando parametrizado
    local shortcut_type=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .type" "$yaml_file" 2>/dev/null)
    
    if [ "$shortcut_type" = "helper" ]; then
        # Comando helper - executar comandos diretamente
        local commands=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .commands[]" "$yaml_file" 2>/dev/null)
        
        # Navegar para o diretório
        cd "$full_path"
        
        # Executar cada comando
        while IFS= read -r command; do
            if [ -n "$command" ]; then
                eval "$command"
                local exit_code=$?
                if [ $exit_code -ne 0 ]; then
                    return $exit_code
                fi
            fi
        done <<< "$commands"
        
        return 0
    elif [ "$shortcut_type" = "parameterized" ]; then
        # Comando parametrizado - coletar parâmetros e processar template
        local parameters=$(collect_parameters "$yaml_file" "$shortcut_name")
        if [ $? -ne 0 ]; then
            return 1
        fi
        
        # Obter template do comando
        local command_template=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .command_template" "$yaml_file" 2>/dev/null)
        
        # Processar template
        local processed_command=$(process_command_template "$command_template" "$parameters" "$yaml_file" "$project_name")
        
        # Verificar se deve mostrar a saída dos comandos
        local show_output=false
        if yq -e ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .show_output" "$yaml_file" >/dev/null 2>&1; then
            show_output=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .show_output" "$yaml_file")
        fi
        
        # Navegar para o diretório
        cd "$full_path"
        
        if [ "$show_output" = "true" ]; then
            # Mostrar saída do comando
            clear
            echo "⚡ Executando comando parametrizado: $shortcut_name"
            echo "📁 Diretório: $full_path"
            echo ""
            echo "════════════════════════════════════════════════════════════════"
            echo ""
            
            # Executar comando processado
            eval "$processed_command"
            local exit_code=$?
            
            if [ $exit_code -eq 0 ]; then
                echo ""
                echo "════════════════════════════════════════════════════════════════"
                echo "✅ Execução concluída com sucesso!"
                echo "════════════════════════════════════════════════════════════════"
                echo ""
                echo "Pressione Enter para continuar..."
                read -r
            else
                echo ""
                echo "════════════════════════════════════════════════════════════════"
                echo "❌ Erro durante a execução!"
                echo "════════════════════════════════════════════════════════════════"
                echo ""
                echo "Pressione Enter para continuar..."
                read -r
            fi
        else
            # Executar sem mostrar saída
            eval "$processed_command" >/dev/null 2>&1
            local exit_code=$?
        fi
        
        # Mostrar resultado
        if [ $exit_code -eq 0 ]; then
            whiptail --title "✅ Sucesso" \
                     --msgbox "Comando parametrizado '$shortcut_name' executado com sucesso!\n\nProjeto: $project_name\nDiretório: $full_path" \
                     12 60
        else
            whiptail --title "❌ Erro" \
                     --msgbox "Erro ao executar o comando parametrizado '$shortcut_name'!\n\nCódigo de saída: $exit_code\n\nVerifique se os parâmetros estão corretos." \
                     12 60
        fi
        
        return $exit_code
    elif [ "$shortcut_type" = "dump" ]; then
        # Comando de dump - usar função execute_dump
        local is_qa="false"
        if [ "$shortcut_name" = "dump-qa" ]; then
            is_qa="true"
        fi
        
        # Executar função execute_dump
        execute_dump "$project_name" "" "$is_qa"
        return $?
    elif [ "$shortcut_type" = "interactive-test" ]; then
        # Comando de teste interativo - usar função execute_interactive_test
        execute_interactive_test "$project_name" "$shortcut_name" "$yaml_file"
        return $?
    fi
    
    # Para todos os outros tipos de comando (test, etc.), executar os comandos do atalho
    # após o setup_shortcut ter sido executado
    
    # Verificar se tem array de comandos ou comando único
    local commands_to_execute=""
    local is_interactive=false
    
    # Verificar se é array de comandos (commands) ou comando único (command)
    if yq -e ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .commands" "$yaml_file" >/dev/null 2>&1; then
        # É um array de comandos - verificar se tem comando interativo
        local commands_array=()
        while IFS= read -r cmd; do
            commands_array+=("$cmd")
            if echo "$cmd" | grep -q "docker exec -it"; then
                is_interactive=true
            fi
        done < <(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .commands[]" "$yaml_file")
        
        # Verificar se deve mostrar a saída dos comandos
        local show_output=false
        if yq -e ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .show_output" "$yaml_file" >/dev/null 2>&1; then
            show_output=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .show_output" "$yaml_file")
        fi
        
        if [ "$is_interactive" = true ]; then
            # Para comandos interativos, limpar tela e executar
            clear
            echo "⚡ Executando comando interativo: $shortcut_name"
            echo "Abrindo nova aba no terminal para o container..."
            sleep 2
            
            # Navegar para o diretório
            cd "$full_path"
            
            # Detectar terminal atual e abrir nova aba
            local terminal_cmd=""
            
            # Verificar qual terminal está sendo usado
            if [ -n "$WARP_SESSION" ] || [ -n "$WARP_TERMINAL" ] || command -v warp-terminal &> /dev/null; then
                # Warp Terminal - instalar xdotool se necessário e usar atalho
                if ! command -v xdotool &> /dev/null; then
                    echo "Instalando xdotool..."
                    sudo apt update && sudo apt install -y xdotool
                fi
                # Construir comando completo para o terminal
                local full_command=""
                for cmd in "${commands_array[@]}"; do
                    full_command="$full_command && $cmd"
                done
                full_command="${full_command# && }" # Remove o primeiro &&
                terminal_cmd="xdotool key ctrl+shift+t && sleep 1 && xdotool type \"cd '$full_path' && $full_command\" && xdotool key Return"
            elif [ -n "$GNOME_TERMINAL_SCREEN" ] || [ -n "$GNOME_TERMINAL_SERVICE" ] || command -v gnome-terminal &> /dev/null; then
                # GNOME Terminal
                local full_command=""
                for cmd in "${commands_array[@]}"; do
                    full_command="$full_command && $cmd"
                done
                full_command="${full_command# && }" # Remove o primeiro &&
                terminal_cmd="gnome-terminal --tab -- bash -c \"cd '$full_path' && $full_command; exec bash\""
            elif [ -n "$KONSOLE_VERSION" ] || command -v konsole &> /dev/null; then
                # Konsole (KDE)
                local full_command=""
                for cmd in "${commands_array[@]}"; do
                    full_command="$full_command && $cmd"
                done
                full_command="${full_command# && }" # Remove o primeiro &&
                terminal_cmd="konsole --new-tab -e bash -c \"cd '$full_path' && $full_command; exec bash\""
            elif [ -n "$TERM_PROGRAM" ] && [[ "$TERM_PROGRAM" == *"iTerm"* ]]; then
                # iTerm2 (macOS)
                local full_command=""
                for cmd in "${commands_array[@]}"; do
                    full_command="$full_command && $cmd"
                done
                full_command="${full_command# && }" # Remove o primeiro &&
                terminal_cmd="osascript -e 'tell application \"iTerm\" to create window with default profile' -e 'tell current session of current window to write text \"cd $full_path && $full_command\"'"
            elif command -v xterm &> /dev/null; then
                # xterm
                local full_command=""
                for cmd in "${commands_array[@]}"; do
                    full_command="$full_command && $cmd"
                done
                full_command="${full_command# && }" # Remove o primeiro &&
                terminal_cmd="xterm -e \"cd '$full_path' && $full_command; exec bash\" &"
            elif command -v alacritty &> /dev/null; then
                # Alacritty
                local full_command=""
                for cmd in "${commands_array[@]}"; do
                    full_command="$full_command && $cmd"
                done
                full_command="${full_command# && }" # Remove o primeiro &&
                terminal_cmd="alacritty --working-directory '$full_path' -e bash -c \"$full_command; exec bash\" &"
            else
                # Fallback: tentar gnome-terminal
                local full_command=""
                for cmd in "${commands_array[@]}"; do
                    full_command="$full_command && $cmd"
                done
                full_command="${full_command# && }" # Remove o primeiro &&
                terminal_cmd="gnome-terminal -- bash -c \"cd '$full_path' && $full_command; exec bash\""
            fi
            
            # Executar comando do terminal
            eval "$terminal_cmd"
            
            # Para comandos interativos, considerar como sucesso
            local exit_code=0
        else
            # Para comandos normais, mostrar barra de progresso apenas se não for para mostrar saída
            if [ "$show_output" != "true" ]; then
                {
                    echo "0"
                    echo "Preparando execução..."
                    sleep 0.2
                    echo "25"
                    echo "Navegando para o diretório..."
                    sleep 0.2
                    echo "50"
                    echo "Executando comandos..."
                    sleep 0.2
                    echo "75"
                    echo "Processando..."
                    sleep 0.2
                    echo "100"
                    echo "Execução concluída!"
                } | whiptail --title "⚡ Executando Atalho" \
                             --gauge "Executando $shortcut_name..." \
                             8 60 0
                else
                    # Limpar tela e mostrar que está executando
                    clear
                    echo "⚡ Executando atalho: $shortcut_name"
                    echo "📁 Diretório: $full_path"
                    echo "📊 Total de comandos: ${#commands_array[@]}"
                    echo ""
                    echo "════════════════════════════════════════════════════════════════"
                    echo ""
                fi
            
            # Navegar para o diretório do projeto
            cd "$full_path"
            
            # Executar cada comando sequencialmente
            local exit_code=0
            local cmd_count=0
            local total_cmds=${#commands_array[@]}
            
            for cmd in "${commands_array[@]}"; do
                cmd_count=$((cmd_count + 1))
                
                if [ "$show_output" = "true" ]; then
                    # Mostrar saída do comando com formatação melhorada
                    echo ""
                    echo "⚡ Executando ($cmd_count/$total_cmds): $cmd"
                    echo "────────────────────────────────────────────────────────────"
                    
                    # Se for uma atribuição de variável, mostrar o valor
                    if echo "$cmd" | grep -q "^[a-zA-Z_][a-zA-Z0-9_]*="; then
                        eval "$cmd"
                        local var_name=$(echo "$cmd" | cut -d'=' -f1)
                        local var_value=$(eval "echo \$$var_name")
                        echo "   → $var_name = '$var_value'"
                    else
                        # Executar comando com configurações otimizadas para responsividade
                        # Configurar variáveis de ambiente para melhor saída
                        export TERM=xterm-256color
                        export FORCE_COLOR=1
                        export COLUMNS=$(tput cols 2>/dev/null || echo 120)
                        export LINES=$(tput lines 2>/dev/null || echo 30)
                        
                        # Executar comando preservando contexto do shell
                        eval "$cmd"
                    fi
                    echo ""
                else
                    # Executar sem mostrar saída
                    eval "$cmd" >/dev/null 2>&1
                fi
                local cmd_exit_code=$?
                if [ $cmd_exit_code -ne 0 ]; then
                    exit_code=$cmd_exit_code
                    break
                fi
            done
            
            # Se show_output estiver ativo e execução foi bem-sucedida, pausar para o usuário
            if [ "$show_output" = "true" ] && [ $exit_code -eq 0 ]; then
                echo ""
                echo "════════════════════════════════════════════════════════════════"
                echo "✅ Execução concluída com sucesso!"
                echo "📊 Comandos executados: $total_cmds"
                echo "⏱️  Status: Finalizado"
                echo "════════════════════════════════════════════════════════════════"
                echo ""
                echo "Pressione Enter para continuar..."
                read -r
            fi
        fi
    else
        # É um comando único
        commands_to_execute="$shortcut_command"
        
        # Verificar se é um comando interativo (contém docker exec -it)
        if echo "$commands_to_execute" | grep -q "docker exec -it"; then
            # Para comandos interativos, limpar tela e executar
            clear
            echo "⚡ Executando comando interativo: $shortcut_name"
            echo "Abrindo nova aba no terminal para o container..."
            sleep 2
            
            # Navegar para o diretório
            cd "$full_path"
            
            # Detectar terminal atual e abrir nova aba
            local terminal_cmd=""
            
            # Verificar qual terminal está sendo usado
            if [ -n "$WARP_SESSION" ] || [ -n "$WARP_TERMINAL" ] || command -v warp-terminal &> /dev/null; then
                # Warp Terminal - instalar xdotool se necessário e usar atalho
                if ! command -v xdotool &> /dev/null; then
                    echo "Instalando xdotool..."
                    sudo apt update && sudo apt install -y xdotool
                fi
                terminal_cmd="xdotool key ctrl+shift+t && sleep 1 && xdotool type \"cd '$full_path' && $commands_to_execute\" && xdotool key Return"
            elif [ -n "$GNOME_TERMINAL_SCREEN" ] || [ -n "$GNOME_TERMINAL_SERVICE" ] || command -v gnome-terminal &> /dev/null; then
                # GNOME Terminal
                terminal_cmd="gnome-terminal --tab -- bash -c \"cd '$full_path' && $commands_to_execute; exec bash\""
            elif [ -n "$KONSOLE_VERSION" ] || command -v konsole &> /dev/null; then
                # Konsole (KDE)
                terminal_cmd="konsole --new-tab -e bash -c \"cd '$full_path' && $commands_to_execute; exec bash\""
            elif [ -n "$TERM_PROGRAM" ] && [[ "$TERM_PROGRAM" == *"iTerm"* ]]; then
                # iTerm2 (macOS)
                terminal_cmd="osascript -e 'tell application \"iTerm\" to create window with default profile' -e 'tell current session of current window to write text \"cd $full_path && $commands_to_execute\"'"
            elif command -v xterm &> /dev/null; then
                # xterm
                terminal_cmd="xterm -e \"cd '$full_path' && $commands_to_execute; exec bash\" &"
            elif command -v alacritty &> /dev/null; then
                # Alacritty
                terminal_cmd="alacritty --working-directory '$full_path' -e bash -c \"$commands_to_execute; exec bash\" &"
            else
                # Fallback: tentar gnome-terminal
                terminal_cmd="gnome-terminal -- bash -c \"cd '$full_path' && $commands_to_execute; exec bash\""
            fi
            
            # Executar comando do terminal
            eval "$terminal_cmd"
            
            # Para comandos interativos, considerar como sucesso
            local exit_code=0
        else
            # Para comandos normais, mostrar barra de progresso
            {
                echo "0"
                echo "Preparando execução..."
                sleep 0.2
                echo "25"
                echo "Navegando para o diretório..."
                sleep 0.2
                echo "50"
                echo "Executando comando: $shortcut_command"
                sleep 0.2
                echo "75"
                echo "Processando..."
                sleep 0.2
                echo "100"
                echo "Execução concluída!"
            } | whiptail --title "⚡ Executando Atalho" \
                         --gauge "Executando $shortcut_name..." \
                         8 60 0
            
            # Executar comando normal
            cd "$full_path" && eval "$commands_to_execute"
            local exit_code=$?
        fi
    fi
    
    if [ $exit_code -eq 0 ]; then
        whiptail --title "✅ Sucesso" \
                 --msgbox "Atalho '$shortcut_name' executado com sucesso!\n\nProjeto: $project_name\nDiretório: $full_path" \
                 12 60
    else
        whiptail --title "❌ Erro" \
                 --msgbox "Erro ao executar o atalho '$shortcut_name'!\n\nCódigo de saída: $exit_code\n\nVerifique se os comandos estão corretos." \
                 12 60
    fi
    
    return $exit_code
}

# Lista caminhos absolutos para shell extras a partir de ~/.zshmap.yml → shell.extras_source (stdout, um por linha).
# Aceita lista (recomendado) ou uma única string; ~ é expandido para $HOME.
_zshmap_yaml_shell_extras_paths() {
    local main_config="$1"
    local query=".shell.extras_source"
    local line t has=0
    [ -f "$main_config" ] || return 0
    t=$(yq -r "$query | type" "$main_config" 2>/dev/null)
    case "$t" in
        array|!!seq)
            while IFS= read -r line; do
                [ -z "$line" ] || [ "$line" = "null" ] && continue
                echo "${line/#\~/$HOME}"
                has=1
            done < <(yq -r "$query[]" "$main_config" 2>/dev/null)
            [ "$has" -eq 1 ] && return 0
            ;;
        string|!!str)
            line=$(yq -r "$query // \"\"" "$main_config" 2>/dev/null)
            if [ -n "$line" ] && [ "$line" != "null" ]; then
                echo "${line/#\~/$HOME}"
            fi
            ;;
    esac
}

# Função para gerar arquivo .zprofile-auto a partir dos projetos dinâmicos
generate_zprofile_auto() {
    local zb_repo_root zb_q output_file projects_dir
    zb_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    zb_q=$(printf '%q' "$zb_repo_root")
    output_file="$zb_repo_root/.zprofile-auto"
    
    # Verificar dependências
    if ! check_yq; then
        return 1
    fi
    
    # Obter diretório de projetos do arquivo de configuração principal
    local main_config="$(_zshmap_home_config_path)"
    # Opcional: script(s) Zsh pessoal(is) — shell.extras_source: string ou lista (ver ~/.zshmap.yml)
    local -a shell_extras_paths=()
    if [ -f "$main_config" ]; then
        projects_dir=$(yq -r ".projects.dir" "$main_config" 2>/dev/null)
        # Expandir ~ para home directory
        projects_dir="${projects_dir/#\~/$HOME}"
        while IFS= read -r _wb_extra_path; do
            [ -n "$_wb_extra_path" ] && shell_extras_paths+=("$_wb_extra_path")
        done < <(_zshmap_yaml_shell_extras_paths "$main_config")
    else
        # Fallback para diretório padrão
        projects_dir="$HOME/Projects"
    fi
    
    # Verificar se o diretório Projects existe
    if [ ! -d "$projects_dir" ]; then
        whiptail --title "❌ Diretório não encontrado" \
                 --msgbox "Diretório $projects_dir não encontrado!\n\nCrie o diretório e adicione seus projetos." \
                 10 60
        return 1
    fi
    
    # Criar cabeçalho do arquivo
    cat > "$output_file" << 'EOF'
# Arquivo .zprofile-auto gerado automaticamente pelo ZshMap
# NÃO EDITE ESTE ARQUIVO MANUALMENTE - Ele será sobrescrito
# Para modificar os atalhos, edite os ficheiros zshmap.yml na raiz de cada projeto

# Funções auxiliares necessárias
function verificar_apache2() {
    if ! command -v apache2 &> /dev/null; then
        true
    else
        sudo service apache2 stop
    fi
}

function notificar() {
    titulo="$1"
    mensagem="$2"
    icone="${3:-info}"
    
    if ! command -v notify-send &> /dev/null; then
        echo -e "\033[31mO pacote notify-send não está instalado. Instalando...\033[0m"
        sudo apt update && sudo apt install -y libnotify-bin
    fi
    
    icone_path="REPLACE_ZSHMAP_REPO_ROOT/images/$icone.png"
    notify-send -i "$icone_path" "$titulo" "$mensagem" --app-name="ZshMap" --urgency=normal --expire-time=500
}

# Função para obter senha do banco de dados do arquivo .env
function get_db_password() {
    local project_root="$1"
    local password_env_var="$2"
    
    local env_file="$project_root/.env"
    
    # Verificar se o arquivo .env existe
    if [ ! -f "$env_file" ]; then
        echo "❌ Arquivo .env não encontrado em: $env_file"
        return 1
    fi
    
    # Buscar a variável de senha no arquivo .env
    local password=$(grep "^$password_env_var=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    
    if [ -z "$password" ]; then
        echo "❌ Variável $password_env_var não encontrada no arquivo .env"
        echo "🔍 Verifique se a variável está definida corretamente no arquivo: $env_file"
        return 1
    fi
    
    echo "$password"
}

# Função para validar parâmetros
validate_parameter() {
    local value="$1"
    local validation="$2"
    local error_message="$3"
    
    if [ -n "$validation" ] && [ "$validation" != "null" ]; then
        if ! echo "$value" | grep -qE "$validation"; then
            whiptail --title "❌ Erro de Validação" \
                     --msgbox "$error_message" \
                     8 60
        return 1
    fi
    fi
    return 0
}

# Função para coletar parâmetros do usuário
collect_parameters() {
    local yaml_file="$1"
    local shortcut_name="$2"
    local parameters=()
    
    local shortcut_title
    shortcut_title=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .title" "$yaml_file" 2>/dev/null)
    [ "$shortcut_title" = "null" ] && shortcut_title="📝 $shortcut_name"
    
    local param_count=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters | length" "$yaml_file" 2>/dev/null)
    
    if [ -z "$param_count" ] || [ "$param_count" = "null" ] || [ "$param_count" = "0" ]; then
        return 0
    fi
    
    for ((i=0; i<param_count; i++)); do
        local param_name=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].name" "$yaml_file" 2>/dev/null)
        local param_type=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].type" "$yaml_file" 2>/dev/null)
        local param_prompt=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].prompt" "$yaml_file" 2>/dev/null)
        local param_required=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].required" "$yaml_file" 2>/dev/null)
        local param_validation=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].validation" "$yaml_file" 2>/dev/null)
        local param_error_message=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].error_message" "$yaml_file" 2>/dev/null)
        local param_placeholder=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].placeholder" "$yaml_file" 2>/dev/null)
        local param_default=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].default" "$yaml_file" 2>/dev/null)
        
        [ "$param_required" = "null" ] && param_required="false"
        [ "$param_validation" = "null" ] && param_validation=""
        [ "$param_error_message" = "null" ] && param_error_message="Valor inválido"
        [ "$param_placeholder" = "null" ] && param_placeholder=""
        [ "$param_default" = "null" ] && param_default=""
        
        local param_value=""
        local valid_input=false
        
        while [ "$valid_input" = false ]; do
            case "$param_type" in
                "input")
                    param_value=""
                    if [ -n "$param_placeholder" ]; then
                        param_value=$(whiptail --title "$shortcut_title" \
                                               --inputbox "$param_prompt\n\nExemplo: $param_placeholder" \
                                               10 60 "$param_default" \
                                               3>&1 1>&2 2>&3)
                    else
                        param_value=$(whiptail --title "$shortcut_title" \
                                               --inputbox "$param_prompt" \
                                               8 60 "$param_default" \
                                               3>&1 1>&2 2>&3)
                    fi
                    local param_input_rc=$?
                    if [ "$param_input_rc" -ne 0 ]; then
                        echo "❌ Entrada cancelada pelo usuário."
                        return 1
                    fi
                    ;;
                "yesno")
                    local yn_rc
                    if [ "$param_default" = "true" ]; then
                        whiptail --title "❓ $param_prompt" \
                                 --yesno "$param_prompt" \
                                 8 60
                        yn_rc=$?
                    else
                        whiptail --title "❓ $param_prompt" \
                                 --no-button "Não" --yes-button "Sim" \
                                 --yesno "$param_prompt" \
                                 8 60
                        yn_rc=$?
                    fi
                    # whiptail: 0=Sim, 1=Não, 255/2+= ESC ou erro → cancelar fluxo
                    if [ "$yn_rc" -gt 1 ]; then
                        echo "❌ Operação cancelada pelo usuário."
                        return 1
                    fi
                    if [ "$yn_rc" -eq 0 ]; then
                        param_value="true"
                    else
                        param_value="false"
                    fi
                    ;;
                *)
                    whiptail --title "❌ Erro" \
                             --msgbox "Tipo de parâmetro não suportado: $param_type" \
                             8 60
                    return 1
                    ;;
            esac
            
            if [ "$param_required" = "true" ] && [ -z "$param_value" ]; then
                whiptail --title "❌ Campo Obrigatório" \
                         --msgbox "O campo '$param_prompt' é obrigatório!" \
                         8 60
                continue
            fi
            
            if [ -n "$param_value" ] && ! validate_parameter "$param_value" "$param_validation" "$param_error_message"; then
                continue
            fi
            
            valid_input=true
        done
        
        parameters+=("$param_name:$param_value")
    done
    
    printf "%s|" "${parameters[@]}"
}

# Função para processar template de comando
process_command_template() {
    local template="$1"
    local parameters="$2"
    local yaml_file="$3"
    local project_name="$4"
    
    # Obter configurações do projeto
    local has_tenants=$(yq -r ".project.has_tenants" "$yaml_file" 2>/dev/null)
    local tenants_dir=$(yq -r ".project.tenants_dir" "$yaml_file" 2>/dev/null)
    local dump_config_bases_path=$(yq -r ".project.dump_config.bases_path" "$yaml_file" 2>/dev/null)
    local dump_config_container=$(yq -r ".project.dump_config.container" "$yaml_file" 2>/dev/null)
    local dump_config_password_env_var=$(yq -r ".project.dump_config.password_env_var" "$yaml_file" 2>/dev/null)
    local dump_config_central_db=$(yq -r ".project.dump_config.central_db" "$yaml_file" 2>/dev/null)
    
    # Converter null para valores padrão
    [ "$has_tenants" = "null" ] && has_tenants="false"
    [ "$tenants_dir" = "null" ] && tenants_dir="storage/app/tenants"
    [ "$dump_config_bases_path" = "null" ] && dump_config_bases_path="~/.multiplier/bases"
    [ "$dump_config_container" = "null" ] && dump_config_container="db.multiplier.local"
    [ "$dump_config_password_env_var" = "null" ] && dump_config_password_env_var="DB01_PASSWORD"
    [ "$dump_config_central_db" = "null" ] && dump_config_central_db="multiplier_central"
    
    local processed_template="$template"
    
    # Substituir variáveis do projeto
    processed_template=$(echo "$processed_template" | sed "s/{{has_tenants}}/$has_tenants/g")
    processed_template=$(echo "$processed_template" | sed "s/{{tenants_dir}}/$tenants_dir/g")
    processed_template=$(echo "$processed_template" | sed "s/{{project_name}}/$project_name/g")
    processed_template=$(echo "$processed_template" | sed "s/{{dump_config_bases_path}}/$dump_config_bases_path/g")
    processed_template=$(echo "$processed_template" | sed "s/{{dump_config_container}}/$dump_config_container/g")
    processed_template=$(echo "$processed_template" | sed "s/{{dump_config_password_env_var}}/$dump_config_password_env_var/g")
    processed_template=$(echo "$processed_template" | sed "s/{{dump_config_central_db}}/$dump_config_central_db/g")
    
    # Substituir parâmetros do usuário
    IFS='|' read -ra PARAMS <<< "$parameters"
    for param in "${PARAMS[@]}"; do
        if [ -n "$param" ]; then
            local param_name=$(echo "$param" | cut -d':' -f1)
            local param_value=$(echo "$param" | cut -d':' -f2-)
            processed_template=$(echo "$processed_template" | sed "s/{{$param_name}}/$param_value/g")
        fi
    done
    
    # Processar condicionais {% if %}
    while echo "$processed_template" | grep -q "{% if"; do
        local if_start=$(echo "$processed_template" | grep -o "{% if [^%]*%}" | head -1)
        local if_condition=$(echo "$if_start" | sed 's/{% if //' | sed 's/ %}//')
        
        local if_end="{% endif %}"
        
        local if_content=$(echo "$processed_template" | sed -n "/$if_start/,/$if_end/p" | sed "1d;$d")
        
        local condition_result=false
        case "$if_condition" in
            "has_tenants")
                [ "$has_tenants" = "true" ] && condition_result=true
                ;;
            *)
                for param in "${PARAMS[@]}"; do
                    if [ -n "$param" ]; then
                        local param_name=$(echo "$param" | cut -d':' -f1)
                        local param_value=$(echo "$param" | cut -d':' -f2-)
                        if [ "$param_name" = "$if_condition" ] && [ "$param_value" = "true" ]; then
                            condition_result=true
                            break
                        fi
                    fi
                done
                ;;
        esac
        
        if [ "$condition_result" = true ]; then
            processed_template=$(echo "$processed_template" | sed "/$if_start/,/$if_end/c\\$if_content")
        else
            processed_template=$(echo "$processed_template" | sed "/$if_start/,/$if_end/d")
        fi
    done
    
    echo "$processed_template"
}


EOF
    sed -i "s|REPLACE_ZSHMAP_REPO_ROOT|${zb_repo_root}|g" "$output_file"

    # Adicionar aliases essenciais solicitados
    cat >> "$output_file" << 'EOF'

# ==============================================
# Aliases essenciais
# ==============================================

# Git
alias gfetch="git fetch --all --prune && git tag -d \$(git tag) && git fetch --tags && for branch in \$(git branch -vv | grep ': gone]' | awk '{print \$1}'); do git branch -D \$branch; done && git pull"
alias branch="git branch --show-current"
alias gps="git push --set-upstream origin \$(git branch --show-current)"

# Terminator
alias working="terminator -l WORKING && exit"
alias work="terminator -l WORK && exit"

# Informações do computador
alias ubuntu="verificar_neofetch"
alias popos="verificar_neofetch"

# Eza
alias eza="verificar_eza"
alias ls="eza --icons --group-directories-first"
alias ll="eza --icons --group-directories-first -l"
alias grep="grep --color"

EOF

    # Gerar atalhos para cada projeto encontrado
    local projects_found=0
    
    # Buscar zshmap.yml (ou workerboss.yml legado) por pasta de projeto
    while IFS= read -r -d '' yaml_path; do
        local project_name=$(basename "$(dirname "$yaml_path")")
        local project_root=$(dirname "$yaml_path")
        
        # Pular o próprio repositório zsh-map (ou clone antigo worker-boss)
        if [ "$project_name" = "zsh-map" ] || [ "$project_name" = "worker-boss" ]; then
            continue
        fi
        
        # Verificar se o arquivo YAML é válido
        if validate_yaml_file "$yaml_path"; then
            echo "" >> "$output_file"
            echo "# ==============================================" >> "$output_file"
            echo "# Atalhos para o projeto: $project_name" >> "$output_file"
            echo "# ==============================================" >> "$output_file"
            echo "" >> "$output_file"
            
            # Gerar atalhos do projeto
            local shortcuts=$(yq -r ".project.shortcuts[] | .name + \"|\" + .path + \"|\" + .type" "$yaml_path" 2>/dev/null)
            
            while IFS= read -r shortcut_line; do
                if [ -n "$shortcut_line" ]; then
                    local shortcut_name=$(echo "$shortcut_line" | cut -d'|' -f1)
                    local shortcut_path=$(echo "$shortcut_line" | cut -d'|' -f2)
                    local shortcut_type=$(echo "$shortcut_line" | cut -d'|' -f3)
                    
                    # Verificar se o atalho tem parâmetros
                    local has_parameters=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters" "$yaml_path" 2>/dev/null)
                    
                    # Verificar se é array de comandos ou comando único
                    local has_commands=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .commands" "$yaml_path" 2>/dev/null)
                    local shortcut_command=""
                    
                    if [ "$has_commands" != "null" ] && [ -n "$has_commands" ]; then
                        # É um array de comandos
                        local commands_array=()
                        while IFS= read -r cmd; do
                            if [ -n "$cmd" ]; then
                                commands_array+=("$cmd")
                            fi
                        done < <(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .commands[]" "$yaml_path" 2>/dev/null)
                        
                        # Construir comando com quebras de linha
                        shortcut_command=$(printf "%s\n" "${commands_array[@]}")
                    else
                        # É um comando único
                        shortcut_command=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .command" "$yaml_path" 2>/dev/null)
                    fi
                    
                    # Construir caminho completo
                    local full_path="$project_root/$shortcut_path"
                    
                    # Verificar se tem setup_shortcut
                    local setup_shortcut=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .setup_shortcut" "$yaml_path" 2>/dev/null)
                    
                    # Verificar se é comando de tipo dump
                    local shortcut_type=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .type" "$yaml_path" 2>/dev/null)
                    
                    if [ "$shortcut_type" = "dump" ]; then
                        # Comando de dump - gerar função especial
                        echo "function $shortcut_name() {" >> "$output_file"
                        echo "    local __wb_prev_dir=\"\$PWD\"" >> "$output_file"
                        echo "    # Comando de dump - usar interface gráfica" >> "$output_file"
                        echo "    cd $zb_q" >> "$output_file"
                        if [ "$shortcut_name" = "dump-qa" ]; then
                            echo "    bash -c 'source ./zsh-map.sh --functions-only && execute_dump \"$project_name\" \"\" \"true\"'" >> "$output_file"
                        else
                            echo "    bash -c 'source ./zsh-map.sh --functions-only && execute_dump \"$project_name\" \"\" \"false\"'" >> "$output_file"
                        fi
                        echo "    local __wb_rc=\$?" >> "$output_file"
                        echo "    cd \"\$__wb_prev_dir\" >/dev/null 2>&1 || true" >> "$output_file"
                        echo "    return \$__wb_rc" >> "$output_file"
                        echo "}" >> "$output_file"
                        echo "" >> "$output_file"
                    elif [ "$shortcut_type" = "interactive-test" ]; then
                        # Mesmo fluxo do helper: whiptail + setup_shortcut + docker exec no container do projeto
                        echo "function $shortcut_name() {" >> "$output_file"
                        echo "    local __wb_prev_dir=\"\$PWD\"" >> "$output_file"
                        echo "    cd $zb_q" >> "$output_file"
                        echo "    bash -c 'source ./zsh-map.sh --functions-only && execute_interactive_test \"$project_name\" \"$shortcut_name\" \"$yaml_path\"'" >> "$output_file"
                        echo "    local __wb_rc=\$?" >> "$output_file"
                        echo "    cd \"\$__wb_prev_dir\" >/dev/null 2>&1 || true" >> "$output_file"
                        echo "    return \$__wb_rc" >> "$output_file"
                        echo "}" >> "$output_file"
                        echo "" >> "$output_file"
                    elif [ "$has_parameters" != "null" ] && [ -n "$has_parameters" ]; then
                        # Atalho com parâmetros dinâmicos
                        echo "function $shortcut_name() {" >> "$output_file"
                        echo "    local __wb_prev_dir=\"\$PWD\"" >> "$output_file"
                        echo "    local param=\"\$1\"" >> "$output_file"
                        echo "    if [ -z \"\$param\" ]; then" >> "$output_file"
                        echo "        echo \"❌ Parâmetro obrigatório não fornecido!\"" >> "$output_file"
                        echo "        echo \"Uso: $shortcut_name <parametro>\"" >> "$output_file"
                        echo "        cd \"\$__wb_prev_dir\" >/dev/null 2>&1 || true" >> "$output_file"
                        echo "        return 1" >> "$output_file"
                        echo "    fi" >> "$output_file"
                        echo "    cd \"$full_path\"" >> "$output_file"
                        # Substituir parâmetros na string de comando
                        # Substituir especificamente o segundo parâmetro vazio ('') pelo parâmetro recebido
                        local modified_command=$(echo "$shortcut_command" | sed "s/execute_dump '\([^']*\)' '' '\([^']*\)'/execute_dump '\1' \"\$param\" '\2'/g")
                        # Escrever comando linha por linha usando printf para evitar problemas de aspas
                        echo "$modified_command" | while IFS= read -r line; do
                            if [ -n "$line" ]; then
                                printf "    %s\n" "$line" >> "$output_file"
                            fi
                        done
                        echo "    local __wb_rc=\$?" >> "$output_file"
                        echo "    cd \"\$__wb_prev_dir\" >/dev/null 2>&1 || true" >> "$output_file"
                        echo "    return \$__wb_rc" >> "$output_file"
                        echo "}" >> "$output_file"
                        echo "" >> "$output_file"
                    else
                        # Atalho sem parâmetros
                        echo "function $shortcut_name() {" >> "$output_file"
                        echo "    local __wb_prev_dir=\"\$PWD\"" >> "$output_file"
                        
                        # Se tem setup_shortcut, executar primeiro
                        if [ "$setup_shortcut" != "null" ] && [ -n "$setup_shortcut" ]; then
                            echo "    # Executando setup_shortcut: $setup_shortcut" >> "$output_file"
                            echo "    cd $zb_q" >> "$output_file"
                            echo "    bash -c 'source ./zsh-map.sh --functions-only && execute_shortcut \"$project_name\" \"$setup_shortcut\"'" >> "$output_file"
                            echo "    if [ \$? -ne 0 ]; then" >> "$output_file"
                            echo "        echo \"❌ Falha ao executar setup_shortcut: $setup_shortcut\"" >> "$output_file"
                            echo "        cd \"\$__wb_prev_dir\" >/dev/null 2>&1 || true" >> "$output_file"
                            echo "        return 1" >> "$output_file"
                            echo "    fi" >> "$output_file"
                            echo "    echo \"✅ Setup shortcut '$setup_shortcut' executado com sucesso\"" >> "$output_file"
                        fi
                        
                        echo "    cd \"$full_path\"" >> "$output_file"
                        # Escrever comando linha por linha usando printf para evitar problemas de aspas
                        echo "$shortcut_command" | while IFS= read -r line; do
                            if [ -n "$line" ]; then
                                printf "    %s\n" "$line" >> "$output_file"
                            fi
                        done
                        echo "    local __wb_rc=\$?" >> "$output_file"
                        echo "    cd \"\$__wb_prev_dir\" >/dev/null 2>&1 || true" >> "$output_file"
                        echo "    return \$__wb_rc" >> "$output_file"
                        echo "}" >> "$output_file"
                        echo "" >> "$output_file"
                    fi
                fi
            done <<< "$shortcuts"
            
            # Gerar comando helper se configurado
            local helper_command=$(yq -r ".project.helper_show_commands" "$yaml_path" 2>/dev/null)
            if [ "$helper_command" != "null" ] && [ -n "$helper_command" ]; then
                echo "function $helper_command() {" >> "$output_file"
                echo "    local __wb_prev_dir=\"\$PWD\"" >> "$output_file"
                echo "    cd \"$project_root\"" >> "$output_file"
                echo "    echo '🚀 Abrindo interface de atalhos do projeto $project_name...'" >> "$output_file"
                echo "    cd $zb_q" >> "$output_file"
                echo "    bash -c 'source ./zsh-map.sh --functions-only && show_project_shortcuts_interface \"$project_name\"'" >> "$output_file"
                echo "    local __wb_rc=\$?" >> "$output_file"
                echo "    cd \"\$__wb_prev_dir\" >/dev/null 2>&1 || true" >> "$output_file"
                echo "    return \$__wb_rc" >> "$output_file"
                echo "}" >> "$output_file"
                echo "" >> "$output_file"
            fi
            
            ((projects_found++))
        fi
    done < <(find_zshmap_project_yamls "$projects_dir")
    
    if [ $projects_found -eq 0 ]; then
        echo "# Nenhum projeto com zshmap.yml (ou workerboss.yml legado) encontrado em $projects_dir" >> "$output_file"
    fi
    
    # Extras pessoais (repositório/dotfiles aparte): após atalhos YAML; ordem = ordem no YAML (lista)
    if [ "${#shell_extras_paths[@]}" -gt 0 ]; then
        echo "" >> "$output_file"
        echo "# ==============================================" >> "$output_file"
        echo "# Extras pessoais — shell.extras_source em ~/.zshmap.yml (lista; um ou vários ficheiros)" >> "$output_file"
        echo "# ==============================================" >> "$output_file"
        local _wb_extra_p _wb_extra_q
        for _wb_extra_p in "${shell_extras_paths[@]}"; do
            _wb_extra_q=$(printf '%q' "$_wb_extra_p")
            echo "if [ -r $_wb_extra_q ]; then" >> "$output_file"
            echo "    . $_wb_extra_q" >> "$output_file"
            echo "fi" >> "$output_file"
            if [ ! -r "$_wb_extra_p" ]; then
                echo "⚠️  zsh-map: shell.extras_source não encontrado ou não legível: $_wb_extra_p" >&2
            fi
        done
    fi
    
    # Adicionar rodapé (path real do clone)
    {
        echo ""
        echo "# =============================================="
        echo "# Instruções de uso"
        echo "# =============================================="
        echo "# Para usar este arquivo:"
        echo "# 1. Execute: source ${zb_repo_root}/.zprofile-auto"
        echo "# 2. Ou adicione ao seu .zprofile: source ${zb_repo_root}/.zprofile-auto"
        echo "#"
        echo "# Para regenerar este arquivo:"
        echo "# Execute o ZshMap e escolha a opção «Gerar .zprofile-auto»"
    } >> "$output_file"

    # Criar link simbólico para .zshrc
    local zshrc_file="$HOME/.zshrc"
    local zprofile_auto_path="$output_file"
    local source_line="# ZshMap - Atalhos automáticos"
    local source_command="source ~/.zprofile-auto"
    
    # Verificar se o .zshrc existe
    if [ ! -f "$zshrc_file" ]; then
        echo "⚠️  Arquivo .zshrc não encontrado em $zshrc_file"
        echo "Arquivo $output_file gerado com sucesso!"
        return 0
    fi
    
    # Verificar se já existe a linha no .zshrc
    if ! grep -q "ZshMap - Atalhos automáticos" "$zshrc_file"; then
        echo "" >> "$zshrc_file"
        echo "$source_line" >> "$zshrc_file"
        echo "$source_command" >> "$zshrc_file"
        echo "✅ Linha adicionada ao .zshrc"
    else
        echo "ℹ️  Linha já existe no .zshrc"
    fi
    
    # Criar link simbólico se não existir
    if [ ! -L "$HOME/.zprofile-auto" ]; then
        ln -sf "$zprofile_auto_path" "$HOME/.zprofile-auto"
        echo "✅ Link simbólico criado: ~/.zprofile-auto -> $zprofile_auto_path"
    else
        echo "ℹ️  Link simbólico já existe"
    fi
    
    echo "Arquivo $output_file gerado com sucesso!"
    echo "🚀 Para usar os atalhos, execute: source ~/.zprofile-auto"
    echo "   ou reinicie o terminal"
    return 0
}

# Função para mostrar interface de atalhos de um projeto específico
show_project_shortcuts_interface() {
    local project_name="$1"
    
    # Verificar dependências
    if ! check_yq; then
        return 1
    fi
    
    # Verificar arquivo YAML
    if ! validate_yaml_file; then
        return 1
    fi
    
    local continue_managing=true
    
    while [ "$continue_managing" = true ]; do
        # Selecionar atalho do projeto específico
        local shortcut_data=$(list_project_shortcuts "$project_name")
        local shortcut_exit_code=$?
        
        # Verificar se o usuário cancelou ou se houve erro
        if [ $shortcut_exit_code -ne 0 ] || [ -z "$shortcut_data" ]; then
            # Usuário cancelou seleção de atalho, perguntar se quer sair
            whiptail --title "🚪 Confirmar Saída" \
                      --yesno "Você realmente deseja sair do gerenciador de atalhos do projeto $project_name?" \
                      8 60
            
            if [ $? -eq 0 ]; then
                continue_managing=false
            fi
            continue
        fi
        
        # Extrair dados do atalho
        local shortcut_name=$(echo "$shortcut_data" | cut -d'|' -f1)
        local shortcut_path=$(echo "$shortcut_data" | cut -d'|' -f2)
        local shortcut_command=$(echo "$shortcut_data" | cut -d'|' -f3)
        
        # Executar atalho diretamente
        execute_shortcut "$project_name" "$shortcut_name" "$shortcut_path" "$shortcut_command"
        
        # Perguntar se quer continuar
        whiptail --title "❓ Continuar?" \
                  --yesno "Deseja executar outro atalho do projeto $project_name?" \
                  8 60
        
        if [ $? -ne 0 ]; then
            continue_managing=false
        fi
    done
}

# Função para executar gerenciador de atalhos dinâmicos
execute_dynamic_shortcuts() {
    # Verificar dependências
    if ! check_yq; then
        return 1
    fi
    
    # Verificar arquivo YAML
    if ! validate_yaml_file; then
        return 1
    fi
    
    local continue_managing=true
    
    while [ "$continue_managing" = true ]; do
        # Selecionar projeto
        local project_name=$(detect_projects)
        local project_exit_code=$?
        
        # Verificar se o usuário cancelou ou se houve erro
        if [ $project_exit_code -ne 0 ] || [ -z "$project_name" ]; then
            whiptail --title "❌ Cancelado" \
                      --msgbox "Seleção de projeto cancelada pelo usuário." \
                      8 50
            return 1
        fi
        
        # Selecionar atalho
        local shortcut_data=$(list_project_shortcuts "$project_name")
        local shortcut_exit_code=$?
        
        # Verificar se o usuário cancelou ou se houve erro
        if [ $shortcut_exit_code -ne 0 ] || [ -z "$shortcut_data" ]; then
            # Usuário cancelou seleção de atalho, perguntar se quer sair
            whiptail --title "🚪 Confirmar Saída" \
                      --yesno "Você realmente deseja sair do gerenciador de atalhos?" \
                      8 60
            
            if [ $? -eq 0 ]; then
                continue_managing=false
            fi
            continue
        fi
        
        # Extrair dados do atalho
        local shortcut_name=$(echo "$shortcut_data" | cut -d'|' -f1)
        local shortcut_path=$(echo "$shortcut_data" | cut -d'|' -f2)
        local shortcut_command=$(echo "$shortcut_data" | cut -d'|' -f3)
        
        # Executar atalho diretamente
        execute_shortcut "$project_name" "$shortcut_name" "$shortcut_path" "$shortcut_command"
        
        # Voltar ao diretório do zsh-map após executar comando
        # Voltar ao diretório do zsh-map após executar comando
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        cd "$script_dir"
        
        # Verificar se é comando interativo - se for, não perguntar se quer continuar
        if echo "$shortcut_command" | grep -q "docker exec -it"; then
            # Para comandos interativos, sair do loop pois o usuário está no container
            continue_managing=false
        else
            # Para comandos normais, perguntar se quer continuar
            whiptail --title "❓ Continuar?" \
                      --yesno "Atalho executado!\n\nDeseja selecionar outro atalho?" \
                      10 60
            
            if [ $? -ne 0 ]; then
                continue_managing=false
            fi
        fi
    done
    
    # Mensagem final
    whiptail --title "✅ Gerenciador de Atalhos" \
              --msgbox "Gerenciador de atalhos finalizado!\n\nObrigado por usar o ZshMap!" \
              10 60
}

# Função para exibir mensagem de boas-vindas
show_welcome() {
    whiptail --title "🚀 ZshMap" \
              --msgbox "Bem-vindo ao ZshMap!\n\nSistema de Automação para Desenvolvedores\n\nEste sistema irá ajudá-lo a configurar e instalar ferramentas essenciais para desenvolvimento." \
              12 60
}

# Função para selecionar sistema operacional ($1 = diretório raiz de programs)
select_operating_system() {
    local prog_root="${1:-}"
    local systems=()
    local count=0
    
    if [ -z "$prog_root" ] || [ ! -d "$prog_root" ]; then
        whiptail --title "❌ Erro" \
                  --msgbox "Diretório de instalação inválido ou inexistente:\n${prog_root:-"(vazio)"}\n\nVerifica install.programs_dir em ~/.zshmap.yml (tem de ser uma **lista** de pastas)." \
                  14 64
        return 1
    fi
    
    # Listar sistemas operacionais disponíveis
    while IFS= read -r system; do
        if [ -n "$system" ]; then
            systems+=("$count" "$system")
            ((count++))
        fi
    done < <(list_directories "$prog_root")
    
    if [ ${#systems[@]} -eq 0 ]; then
        whiptail --title "❌ Erro" \
                  --msgbox "Nenhum subdiretório de SO encontrado em:\n$prog_root\n\nCrie pastas (ex.: ubuntu/) com scripts .sh dentro, ou ajuste install.programs_dir." \
                  14 64
        return 1
    fi
    
    # Mostrar menu de seleção do sistema operacional
    local choice=$(whiptail --title "🖥️  Selecionar Sistema Operacional" \
                           --menu "Escolha seu sistema operacional:" \
                           20 60 10 \
                           "${systems[@]}" \
                           3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$choice" ] && [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "$choice"
    else
        return 1
    fi
}

# Função para selecionar scripts ($1 = raiz programs, $2 = nome do subdir SO, ex. ubuntu)
select_scripts() {
    local prog_root="${1:-}"
    local system_dir="$2"
    local scripts=()
    local count=0
    
    if [ -z "$prog_root" ] || [ -z "$system_dir" ]; then
        return 1
    fi
    
    # Listar scripts disponíveis
    while IFS= read -r script; do
        if [ -n "$script" ]; then
            # Formatar nome do script (remover prefixo numérico se existir)
            local display_name="$script"
            if [[ "$script" =~ ^[0-9]+- ]]; then
                display_name="${script#*-}"
            fi
            
            scripts+=("$count" "$display_name")
            ((count++))
        fi
    done < <(list_scripts "${prog_root%/}/$system_dir")
    
    if [ ${#scripts[@]} -eq 0 ]; then
        whiptail --title "❌ Erro" \
                  --msgbox "Nenhum script encontrado para o sistema $system_dir!\n\nVerifique se existem arquivos .sh neste diretório." \
                  10 60
        return 1
    fi
    
    # Mostrar menu de seleção dos scripts
    local choice=$(whiptail --title "📦 Selecionar Script" \
                           --menu "Escolha o script a ser executado:" \
                           20 60 12 \
                           "${scripts[@]}" \
                           3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$choice" ] && [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "$choice"
    else
        return 1
    fi
}

# Função para executar instalação de programas
execute_programs() {
    local continue_installing=true
    local system_dir=""
    local prog_root
    
    if ! _zshmap_programs_has_any_sh; then
        whiptail --title "❌ Instalação de programas" \
                  --msgbox "Não há scripts de instalação disponíveis.\n\nEm ~/.zshmap.yml, install.programs_dir tem de ser uma **lista** (YAML array) de pastas — cada pasta com subpastas por SO (ex.: ubuntu/) e ficheiros .sh.\n\nExemplo:\n  programs_dir:\n    - \"~/repo-a/programs\"\n    - \"~/repo-b/outros\"\n\nÉ preciso yq no PATH para ler o YAML." \
                  20 72
        return 1
    fi
    
    prog_root=$(_zshmap_programs_choose_root_interactive)
    if [ $? -ne 0 ] || [ -z "$prog_root" ]; then
        whiptail --title "❌ Cancelado" \
                  --msgbox "Não foi escolhida nenhuma pasta de scripts de instalação." \
                  8 58
        return 1
    fi
    
    while [ "$continue_installing" = true ]; do
        # Selecionar sistema operacional (apenas na primeira vez)
        if [ -z "$system_dir" ]; then
            local system_choice=$(select_operating_system "$prog_root")
            local choice_exit_code=$?
            
            # Verificar se o usuário cancelou ou se houve erro
            if [ $choice_exit_code -ne 0 ] || [ -z "$system_choice" ]; then
                whiptail --title "❌ Cancelado" \
                          --msgbox "Seleção de sistema operacional cancelada pelo usuário." \
                          8 50
                return 1
            fi
            
            # Verificar se system_choice é um número válido
            if ! [[ "$system_choice" =~ ^[0-9]+$ ]]; then
                whiptail --title "❌ Erro" \
                          --msgbox "Seleção inválida de sistema operacional!" \
                          8 50
                return 1
            fi
            
            # Obter nome do diretório do sistema
            system_dir=""
            local count=0
            while IFS= read -r system; do
                if [ -n "$system" ]; then
                    if [ "$count" -eq "$system_choice" ]; then
                        system_dir="$system"
                        break
                    fi
                    ((count++))
                fi
            done < <(list_directories "$prog_root")
            
            if [ -z "$system_dir" ]; then
                whiptail --title "❌ Erro" \
                          --msgbox "Sistema operacional não encontrado!" \
                          8 50
                return 1
            fi
        fi
        
        # Selecionar script
        local script_choice=$(select_scripts "$prog_root" "$system_dir")
        local script_exit_code=$?
        
        # Verificar se o usuário cancelou ou se houve erro
        if [ $script_exit_code -ne 0 ] || [ -z "$script_choice" ]; then
            # Usuário cancelou seleção de script, perguntar se quer sair
            whiptail --title "🚪 Confirmar Saída" \
                      --yesno "Você realmente deseja sair da instalação de programas?" \
                      8 60
            
            if [ $? -eq 0 ]; then
                continue_installing=false
            fi
            continue
        fi
        
        # Verificar se script_choice é um número válido
        if ! [[ "$script_choice" =~ ^[0-9]+$ ]]; then
            whiptail --title "❌ Erro" \
                      --msgbox "Seleção inválida de script!" \
                      8 50
            continue
        fi
        
        # Obter nome do script
        local script_name=""
        local count=0
        while IFS= read -r script; do
            if [ -n "$script" ]; then
                if [ "$count" -eq "$script_choice" ]; then
                    script_name="$script"
                    break
                fi
                ((count++))
            fi
        done < <(list_scripts "${prog_root%/}/$system_dir")
        
        if [ -z "$script_name" ]; then
            whiptail --title "❌ Erro" \
                      --msgbox "Script não encontrado!" \
                      8 50
            continue
        fi
        
        # Formatar nome para exibição
        local display_name="$script_name"
        if [[ "$script_name" =~ ^[0-9]+- ]]; then
            display_name="${script_name#*-}"
        fi
        
        # Confirmar execução
        whiptail --title "⚠️  Confirmar Execução" \
                  --yesno "O script $display_name será executado no seu $system_dir!\n\n⚠️  ATENÇÃO: Esta operação pode demorar alguns minutos\n\nDeseja continuar?" \
                  12 60
        
        if [ $? -ne 0 ]; then
            whiptail --title "❌ Cancelado" \
                      --msgbox "Execução cancelada pelo usuário." \
                      8 50
            continue
        fi
        
        # Executar script
        execute_script "$prog_root" "$system_dir" "$script_name" "$display_name"
        
        # Perguntar se quer continuar instalando
        whiptail --title "❓ Continuar Instalando?" \
                  --yesno "Programa $display_name instalado com sucesso!\n\nDeseja continuar selecionando outros programas para instalar?" \
                  10 60
        
        if [ $? -ne 0 ]; then
            continue_installing=false
        fi
    done
    
    # Mensagem final
    whiptail --title "✅ Instalação Concluída" \
              --msgbox "Processo de instalação de programas finalizado!\n\nTodos os programas selecionados foram instalados com sucesso no seu $system_dir." \
              10 60
}

# Função para executar script específico ($1 = raiz programs, $2 = SO, $3 = ficheiro .sh, $4 = nome amigável)
execute_script() {
    local prog_root="${1:-}"
    local system_dir="$2"
    local script_name="$3"
    local display_name="$4"
    local script_path="${prog_root%/}/$system_dir/$script_name"
    
    if [ ! -f "$script_path" ]; then
        whiptail --title "❌ Erro" \
                  --msgbox "Script $script_path não encontrado!" \
                  8 50
        return 1
    fi
    
    # Solicitar senha do sudo se necessário
    local sudo_password=""
    if [ "$EUID" -ne 0 ]; then
        sudo_password=$(get_sudo_password)
        if [ $? -ne 0 ]; then
            whiptail --title "❌ Cancelado" \
                      --msgbox "Execução cancelada - autenticação necessária!" \
                      8 50
            return 1
        fi
    fi
    
    # Mostrar barra de progresso
    {
        echo "0"
        echo "Iniciando execução..."
        sleep 0.2
        echo "25"
        echo "Verificando permissões..."
        sleep 0.2
        echo "50"
        echo "Executando script: $display_name"
        sleep 0.2
        echo "75"
        echo "Processando instalação..."
        sleep 0.2
        echo "100"
        echo "Execução concluída!"
    } | whiptail --title "📦 Executando $display_name" \
                  --gauge "Executando script..." \
                  8 60 0
    
    # Executar script com ou sem sudo
    local exit_code=0
    if [ -n "$sudo_password" ]; then
        # Executar com sudo usando senha fornecida
        echo "$sudo_password" | sudo -S sh "$script_path" 2>/dev/null
        exit_code=$?
    else
        # Executar diretamente (usuário root)
        sh "$script_path"
        exit_code=$?
    fi
    
    if [ $exit_code -eq 0 ]; then
        whiptail --title "✅ Sucesso" \
                  --msgbox "Execução de $display_name concluída com sucesso!\n\nO script foi executado no seu $system_dir." \
                  10 60
    else
        whiptail --title "❌ Erro" \
                  --msgbox "Erro durante a execução de $display_name!\n\nVerifique os logs para mais detalhes." \
                  10 60
    fi
}

# Detecta uso de SSH para Git: 1Password, chaves locais, ssh-agent ou indefinido.
# Imprime uma linha curta em PT-BR para exibição (sem newline extra).
_zshmap_git_ssh_summary_line() {
    local ssh_dir="${HOME}/.ssh"
    local ssh_config="${ssh_dir}/config"
    local git_ssh_cmd
    git_ssh_cmd=$(git config --global --get core.sshCommand 2>/dev/null || true)

    local uses_onepassword=false
    if [ -n "$git_ssh_cmd" ]; then
        if echo "$git_ssh_cmd" | grep -qiE '1password|\.1password|op-ssh|op ssh'; then
            uses_onepassword=true
        fi
    fi
    if [ "$uses_onepassword" = false ] && [ -f "$ssh_config" ]; then
        if grep -vE '^\s*#' "$ssh_config" 2>/dev/null | grep -qiE 'IdentityAgent.*1password|IdentityAgent.*\.1password|op-ssh-sign'; then
            uses_onepassword=true
        fi
    fi
    local sock="${SSH_AUTH_SOCK:-}"
    if [ "$uses_onepassword" = false ] && [ -n "$sock" ]; then
        if echo "$sock" | grep -qiE '1password|\.1password|op-ssh'; then
            uses_onepassword=true
        fi
    fi

    local has_local_key=false
    if [ -d "$ssh_dir" ]; then
        local f
        for f in "$ssh_dir"/id_ed25519 "$ssh_dir"/id_rsa "$ssh_dir"/id_ecdsa "$ssh_dir"/id_dsa; do
            if [ -f "$f" ]; then
                has_local_key=true
                break
            fi
        done
    fi

    local agent_has_keys=false
    if [ -n "$sock" ] && command -v ssh-add >/dev/null 2>&1; then
        if ssh-add -l >/dev/null 2>&1; then
            agent_has_keys=true
        fi
    fi

    if [ "$uses_onepassword" = true ]; then
        if [ "$has_local_key" = true ]; then
            printf '%s' '🔐 SSH: agente 1Password (+ chaves locais em ~/.ssh)'
        else
            printf '%s' '🔐 SSH: agente 1Password (IdentityAgent / socket)'
        fi
        return 0
    fi

    if [ "$has_local_key" = true ]; then
        printf '%s' '🔑 SSH: chaves privadas em ~/.ssh'
        return 0
    fi

    if [ "$agent_has_keys" = true ]; then
        printf '%s' '🔑 SSH: chaves carregadas no ssh-agent'
        return 0
    fi

    printf '%s' '⚠️ SSH: não detectado (Git por HTTPS ou SSH fora do perfil usual)'
}

# Formata user.signingkey para exibição no Whiptail (várias linhas curtas).
_zshmap_git_format_signingkey_display() {
    local key="$1"
    [ -z "$key" ] && return 1

    # Caminho para arquivo (.pub / key)
    if [[ "$key" == /* ]] || [[ "$key" == ./* ]] || [[ "$key" =~ ^~/. ]] || [[ "$key" == "${HOME}/.ssh/"* ]]; then
        printf '%s\n' '   📎 Origem: arquivo'
        printf '%s\n' "      ${key/#\~/$HOME}"
        return 0
    fi

    # Chave pública SSH em uma linha
    local algo_word blob
    algo_word=$(echo "$key" | awk '{print $1}')
    blob=$(echo "$key" | awk '{print $2}')
    if [ -n "$algo_word" ] && [ -n "$blob" ]; then
        local is_ssh_pub=false
        if [[ "$algo_word" == ssh-rsa ]] || [[ "$algo_word" == ssh-ed25519 ]] || [[ "$algo_word" == ssh-dss ]]; then
            is_ssh_pub=true
        elif [[ "$algo_word" == ecdsa-sha2-* ]]; then
            is_ssh_pub=true
        fi

        if [ "$is_ssh_pub" = true ]; then
            local algo_human="RSA"
            case "$algo_word" in
                ssh-rsa) algo_human="RSA" ;;
                ssh-ed25519) algo_human="Ed25519" ;;
                ssh-dss) algo_human="DSA" ;;
                ecdsa-sha2-*) algo_human="ECDSA" ;;
            esac
            local blen=${#blob}
            local start="$blob"
            local end=""
            if [ "$blen" -gt 46 ]; then
                start="${blob:0:28}"
                end="${blob: -14}"
            fi
            printf '%s\n' '   🔑 Chave pública SSH (assinatura)'
            printf '%s\n' "      Algoritmo: $algo_human · $algo_word"
            if [ -n "$end" ]; then
                printf '%s\n' "      Corpo:     ${start} … ${end}"
            else
                printf '%s\n' "      Corpo:     $blob"
            fi
            printf '%s\n' "      (${blen} caracteres base64)"
            return 0
        fi
    fi

    # Id hex OpenPGP / fingerprint curto
    if [[ "$key" =~ ^[A-Fa-f0-9]{8,}$ ]]; then
        printf '%s\n' '   🔑 Identificador OpenPGP'
        printf '%s\n' "      $key"
        return 0
    fi

    # Fallback
    local k_short="$key"
    if [ "${#key}" -gt 56 ]; then
        k_short="${key:0:53}..."
    fi
    printf '%s\n' '   🔑 user.signingkey'
    printf '%s\n' "      $k_short"
    return 0
}

# Resumo da assinatura de commits (GPG OpenPGP ou SSH).
_zshmap_git_signing_summary_lines() {
    local gpgsign
    gpgsign=$(git config --global --get commit.gpgsign 2>/dev/null || true)
    local gpg_format
    gpg_format=$(git config --global --get gpg.format 2>/dev/null || true)
    local signingkey
    signingkey=$(git config --global --get user.signingkey 2>/dev/null || true)
    local tag_sign
    tag_sign=$(git config --global --get tag.gpgSign 2>/dev/null || true)

    if [ "$gpgsign" = "true" ] || [ "$gpgsign" = "1" ]; then
        local fmt_display="OpenPGP (GPG)"
        if [ "$gpg_format" = "ssh" ]; then
            fmt_display="SSH"
        elif [ -n "$gpg_format" ] && [ "$gpg_format" != "openpgp" ]; then
            fmt_display="$gpg_format"
        fi
        printf '%s\n' "✍️ Commits assinados: ✅ ($fmt_display)"
        if [ -n "$signingkey" ]; then
            _zshmap_git_format_signingkey_display "$signingkey"
        else
            printf '%s\n' '   ⚠️ user.signingkey não definido — revise o Git'
        fi
    else
        printf '%s\n' '✍️ Commits assinados: não (commit.gpgsign desligado)'
        if [ -n "$signingkey" ]; then
            printf '%s\n' '   Observação: user.signingkey está definido:'
            _zshmap_git_format_signingkey_display "$signingkey"
        fi
    fi

    if [ "$tag_sign" = "true" ] || [ "$tag_sign" = "1" ]; then
        printf '%s\n' '🏷️ Tags assinadas: ✅ (tag.gpgSign)'
    elif [ -n "$tag_sign" ]; then
        printf '%s\n' "🏷️ Tags assinadas: não (tag.gpgSign=$tag_sign)"
    fi
}

# Função para exibir informações sobre configuração Git
show_git_info() {
    # Verificar configurações atuais do Git
    local current_name=$(git config --global user.name 2>/dev/null || echo "Não configurado")
    local current_email=$(git config --global user.email 2>/dev/null || echo "Não configurado")
    local current_editor=$(git config --global core.editor 2>/dev/null || echo "Não configurado")

    local ssh_summary
    ssh_summary=$(_zshmap_git_ssh_summary_line)
    local signing_block
    signing_block=$(_zshmap_git_signing_summary_lines)

    local git_ssh_cmd_display=""
    local git_ssh_cmd_val
    git_ssh_cmd_val=$(git config --global --get core.sshCommand 2>/dev/null || true)
    if [ -n "$git_ssh_cmd_val" ]; then
        local gsc_short="$git_ssh_cmd_val"
        if [ "${#git_ssh_cmd_val}" -gt 48 ]; then
            gsc_short="${git_ssh_cmd_val:0:45}..."
        fi
        git_ssh_cmd_display="\n🔧 core.sshCommand: $gsc_short"
    fi
    
    # Determinar se já existe configuração
    local has_config="false"
    if [[ "$current_name" != "Não configurado" && "$current_email" != "Não configurado" ]]; then
        has_config="true"
    fi
    
    # Criar mensagem baseada no status atual
    local message=""
    if [[ "$has_config" == "true" ]]; then
        message="📋 Configurações atuais do Git:\n\n👤 Nome: $current_name\n📧 Email: $current_email\n✏️  Editor: $current_editor\n\n$ssh_summary$git_ssh_cmd_display\n\n$signing_block\n\nEste módulo permite:\n• Alterar nome de usuário\n• Alterar email\n• Configurar editor padrão\n• Aplicar configurações básicas\n\nDeseja continuar?"
    else
        message="Este módulo irá configurar:\n\n• Nome de usuário\n• Email\n• Editor padrão\n• Configurações básicas do Git\n\n📎 Situação atual detectada:\n$ssh_summary$git_ssh_cmd_display\n\n$signing_block\n\n⚠️  ATENÇÃO: Será solicitado seu nome e email\n\nDeseja continuar?"
    fi
    
    whiptail --title "🔧 Configuração Git Local" \
              --yesno "$message" \
              32 74
    
    return $?
}

# Função para executar configuração Git
execute_git() {
    if show_git_info; then
        # Obter configurações atuais
        local current_name=$(git config --global user.name 2>/dev/null || echo "")
        local current_email=$(git config --global user.email 2>/dev/null || echo "")
        local current_editor=$(git config --global core.editor 2>/dev/null || echo "")
        
        # Mostrar barra de progresso
        {
            echo "0"
            echo "Iniciando configuração Git..."
            sleep 0.2
            echo "50"
            echo "Configurando Git local..."
            sleep 0.2
            echo "100"
            echo "Configuração concluída!"
        } | whiptail --title "🔧 Configurando Git" \
                     --gauge "Configurando Git..." \
                     8 60 0
        
        # Solicitar nome do usuário (com valor atual como padrão)
        local user_name=$(whiptail --title "👤 Nome do Usuário Git" \
                                   --inputbox "Digite seu nome para a configuração Git:\n\nExemplo: João Silva" \
                                   10 60 \
                                   "$current_name" \
                                   3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ] || [ -z "$user_name" ]; then
            whiptail --title "❌ Cancelado" \
                      --msgbox "Configuração de nome cancelada pelo usuário." \
                      8 50
            return 1
        fi
        
        # Solicitar email do usuário (com valor atual como padrão)
        local user_email=$(whiptail --title "📧 Email do Usuário Git" \
                                    --inputbox "Digite seu email para a configuração Git:\n\nExemplo: joao@exemplo.com" \
                                    10 60 \
                                    "$current_email" \
                                    3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ] || [ -z "$user_email" ]; then
            whiptail --title "❌ Cancelado" \
                      --msgbox "Configuração de email cancelada pelo usuário." \
                      8 50
            return 1
        fi
        
        # Solicitar editor padrão (com valor atual como padrão)
        local user_editor=$(whiptail --title "✏️  Editor Padrão do Git" \
                                     --inputbox "Digite o editor padrão para o Git:\n\nExemplos:\n• nvim (Neovim)\n• vim\n• code (VS Code)\n• nano" \
                                     12 60 \
                                     "$current_editor" \
                                     3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then
            whiptail --title "❌ Cancelado" \
                      --msgbox "Configuração de editor cancelada pelo usuário." \
                      8 50
            return 1
        fi
        
        # Confirmar configuração
        whiptail --title "⚠️  Confirmar Configuração Git" \
                  --yesno "Confirme as informações:\n\n👤 Nome: $user_name\n📧 Email: $user_email\n✏️  Editor: $user_editor\n\nDeseja aplicar essas configurações?" \
                  14 60
        
        if [ $? -ne 0 ]; then
            whiptail --title "❌ Cancelado" \
                      --msgbox "Configuração Git cancelada pelo usuário." \
                      8 50
            return 1
        fi
        
        # Aplicar configurações Git
        {
            echo "0"
            echo "Aplicando configurações..."
            sleep 0.2
            echo "25"
            echo "Configurando nome do usuário..."
            git config --global user.name "$user_name"
            sleep 0.2
            echo "50"
            echo "Configurando email do usuário..."
            git config --global user.email "$user_email"
            sleep 0.2
            echo "75"
            echo "Configurando editor padrão..."
            git config --global core.editor "$user_editor"
            sleep 0.2
            echo "100"
            echo "Configuração concluída!"
        } | whiptail --title "🔧 Aplicando Configurações Git" \
                     --gauge "Aplicando configurações..." \
                     8 60 0
        
        # Verificar se a configuração foi bem-sucedida
        if git config --global user.name >/dev/null 2>&1 && git config --global user.email >/dev/null 2>&1; then
            # Mostrar configurações aplicadas
            local current_name=$(git config --global user.name)
            local current_email=$(git config --global user.email)
            local current_editor=$(git config --global core.editor)
            
            whiptail --title "✅ Configuração Git Concluída" \
                      --msgbox "Configuração Git realizada com sucesso!\n\n👤 Nome: $current_name\n📧 Email: $current_email\n✏️  Editor: $current_editor\n\nSuas configurações Git estão prontas para uso!" \
                      14 60
        else
            whiptail --title "❌ Erro na Configuração" \
                      --msgbox "Erro durante a configuração Git!\n\nVerifique se o Git está instalado e se você tem permissões adequadas." \
                      10 60
        fi
    fi
}

# Função para exibir informações sobre dependências ZSH
show_zsh_info() {
    whiptail --title "🐚 Dependências do ZSH" \
              --yesno "Este módulo irá instalar:\n\n• Oh My Zsh\n• Plugins úteis\n• Temas personalizados\n• Ferramentas de produtividade\n\n⚠️  ATENÇÃO: Esta operação pode demorar alguns minutos\n\nDeseja continuar?" \
              16 60
    
    return $?
}

# Função para executar dependências ZSH
execute_zsh() {
    if show_zsh_info; then
        # Mostrar barra de progresso
        {
            echo "0"
            echo "Iniciando instalação ZSH..."
            sleep 0.2
            echo "25"
            echo "Instalando Oh My Zsh..."
            sleep 0.2
            echo "50"
            echo "Configurando plugins..."
            sleep 0.2
            echo "75"
            echo "Aplicando temas..."
            sleep 0.2
            echo "100"
            echo "Instalação concluída!"
        } | whiptail --title "🐚 Instalando ZSH" \
                     --gauge "Instalando dependências ZSH..." \
                     8 60 0
        
        # Executar instalação ZSH
        if [ -f "./zsh-dependencies.sh" ]; then
            ./zsh-dependencies.sh
            whiptail --title "✅ Sucesso" \
                     --msgbox "Instalação das dependências ZSH concluída com sucesso!\n\nSeu ZSH está configurado com plugins e temas úteis." \
                     10 60
        else
            whiptail --title "❌ Erro" \
                     --msgbox "Script zsh-dependencies.sh não encontrado!\n\nVerifique se o arquivo existe no diretório atual." \
                     10 60
        fi
    fi
}

# Função para mostrar informações sobre atalhos customizados
show_shortcuts_info() {
    whiptail --title "🔧 Atalhos Customizados" \
              --yesno "Este módulo irá exibir todos os atalhos personalizados disponíveis no seu sistema.\n\nOs atalhos incluem:\n• Comandos de projetos (Multiplier, VolleyTrack, etc.)\n• Atalhos de sistema\n• Comandos Git\n• Ferramentas de desenvolvimento\n\nDeseja continuar?" \
              16 60
    
    return $?
}

# Função para executar exibição de atalhos
execute_shortcuts() {
    if show_shortcuts_info; then
        # Mostrar barra de progresso
        {
            echo "0"
            echo "Carregando atalhos personalizados..."
            sleep 0.2
            echo "50"
            echo "Processando aliases do .zprofile..."
            sleep 0.2
            echo "100"
            echo "Atalhos carregados!"
        } | whiptail --title "🔧 Carregando Atalhos" \
                     --gauge "Carregando atalhos..." \
                     8 60 0
        
        # Executar comando atalhos
        # Tentar executar o comando atalhos de forma segura
        local shortcuts_output=""
        
        # Tentar executar o alias atalhos diretamente do .zprofile
        shortcuts_output=$(bash -c "source ~/.zprofile 2>/dev/null && atalhos" 2>/dev/null)
        
        # Se não conseguiu, tentar extrair e executar o conteúdo do alias
        if [ -z "$shortcuts_output" ]; then
            # Extrair o conteúdo do alias atalhos do .zprofile
            local alias_start=$(grep -n "alias atalhos=" ~/.zprofile | cut -d: -f1)
            local alias_end=$(grep -n '^"' ~/.zprofile | tail -1 | cut -d: -f1)
            
            if [ -n "$alias_start" ] && [ -n "$alias_end" ]; then
                # Extrair o conteúdo do alias (linhas entre alias_start+1 e alias_end-1)
                local alias_content=$(sed -n "$((alias_start+1)),$((alias_end-1))p" ~/.zprofile)
                shortcuts_output=$(bash -c "$alias_content" 2>/dev/null)
            fi
        fi
        
        if [ -n "$shortcuts_output" ]; then
            # Exibir os atalhos em uma caixa de texto
            whiptail --title "🔧 Atalhos Personalizados Disponíveis" \
                      --scrolltext \
                      --msgbox "$shortcuts_output" \
                      25 80
        else
            whiptail --title "❌ Erro" \
                      --msgbox "Não foi possível carregar os atalhos personalizados!\n\nVerifique se:\n• O .zprofile está carregado corretamente\n• O alias 'atalhos' está definido\n• Não há erros de sintaxe no .zprofile" \
                      12 60
        fi
    fi
}

# Função para mostrar informações do sistema em tempo real
show_system_info_realtime() {
    # Variáveis para armazenar valores máximos
    local max_memory=0
    local max_cpu=0
    local max_swap=0
    local max_disk_read=0
    local max_disk_write=0
    local max_network_rx=0
    local max_network_tx=0
    
    # Variáveis para cálculo de delta (rede e disco)
    local prev_network_rx=0
    local prev_network_tx=0
    local prev_disk_read=0
    local prev_disk_write=0
    local first_measurement=true
    local start_time=$(date +%s)
    
    # Função para capturar Ctrl+C e mostrar resultados
    trap 'show_realtime_results; if [ $? -eq 1 ]; then continue_monitoring=true; else continue_monitoring=false; fi' INT
    
    # Função para mostrar resultados finais
    show_realtime_results() {
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local hours=$((elapsed / 3600))
        local minutes=$(((elapsed % 3600) / 60))
        local seconds=$((elapsed % 60))
        
        local time_str=""
        if [ $hours -gt 0 ]; then
            time_str="${hours}h ${minutes}m ${seconds}s"
        elif [ $minutes -gt 0 ]; then
            time_str="${minutes}m ${seconds}s"
        else
            time_str="${seconds}s"
        fi
        
        # Mostrar interface de resultados
        local results_message=""
        results_message+="📈 MONITOR DE PERFORMANCE - RESULTADOS FINAIS\n\n"
        results_message+="⏱️  Tempo de monitoramento: $time_str\n\n"
        local current_mem_used=$(free -m | grep '^Mem\.:' | awk '{print $3}')
        local current_mem_total=$(free -m | grep '^Mem\.:' | awk '{print $2}')
        results_message+="🧠 MEMÓRIA RAM\n"
        results_message+="• Uso atual: $current_mem_used MB ($(convert_mb_to_gb $current_mem_used))\n"
        results_message+="• Pico máximo: $max_memory MB ($(convert_mb_to_gb $max_memory))\n"
        results_message+="• Total disponível: $current_mem_total MB ($(convert_mb_to_gb $current_mem_total))\n\n"
        results_message+="⚡ CPU\n"
        results_message+="• Uso atual: $(top -bn1 | grep "%CPU(s):" | awk '{print $2}' | sed 's/%us,//')%\n"
        results_message+="• Pico máximo: $max_cpu%\n\n"
        local current_swap_used=$(free -m | grep '^Swap:' | awk '{print $3}')
        local current_swap_total=$(free -m | grep '^Swap:' | awk '{print $2}')
        results_message+="💾 SWAP\n"
        results_message+="• Uso atual: $current_swap_used MB ($(convert_mb_to_gb $current_swap_used))\n"
        results_message+="• Pico máximo: $max_swap MB ($(convert_mb_to_gb $max_swap))\n"
        results_message+="• Total disponível: $current_swap_total MB ($(convert_mb_to_gb $current_swap_total))\n\n"
        results_message+="💿 DISCO\n"
        results_message+="• Leitura máxima: $max_disk_read KB/s\n"
        results_message+="• Escrita máxima: $max_disk_write KB/s\n\n"
        results_message+="🌐 REDE\n"
        results_message+="• Recebido máximo: $max_network_rx bytes\n"
        results_message+="• Enviado máximo: $max_network_tx bytes\n\n"
        results_message+="✅ Monitoramento finalizado com sucesso!"
        
        whiptail --title "📈 Resultados do Monitoramento" \
                 --scrolltext \
                 --yes-button "Voltar ao Monitoramento" \
                 --no-button "Voltar ao Menu Principal" \
                 --yesno "$results_message" \
                 25 80
        
        if [ $? -eq 0 ]; then
            # Usuário escolheu "Voltar ao Monitoramento"
            # Reconfigurar trap para continuar monitoramento
            trap 'show_realtime_results; if [ $? -eq 1 ]; then continue_monitoring=true; else continue_monitoring=false; fi' INT
            return 1
        else
            # Usuário escolheu "Voltar ao Menu Principal"
            trap - INT
            return 0
        fi
    }
    
    # Função para converter MB para GB (otimizada)
    convert_mb_to_gb() {
        local mb_value="$1"
        # Usar aritmética do bash em vez de bc para ser mais rápido
        local gb_value=$((mb_value * 100 / 1024))
        local gb_int=$((gb_value / 100))
        local gb_dec=$((gb_value % 100))
        printf "%d.%02d GB" $gb_int $gb_dec
    }
    
    # Função para obter métricas atuais
    get_current_metrics() {
        local prev_rx="$1"
        local prev_tx="$2"
        local prev_disk_r="$3"
        local prev_disk_w="$4"
        local is_first="$5"
        # Memória (formato português: Mem.:)
        local memory_info=$(free -m | grep '^Mem\.:')
        local memory_used=$(echo "$memory_info" | awk '{print $3}' 2>/dev/null || echo "0")
        local memory_total=$(echo "$memory_info" | awk '{print $2}' 2>/dev/null || echo "1")
        local memory_percent=0
        if [ "$memory_total" -gt 0 ]; then
            memory_percent=$((memory_used * 100 / memory_total))
        fi
        
        # CPU - usar método mais confiável
        local cpu_percent=0
        if command -v vmstat &> /dev/null; then
            # Usar vmstat para obter uso de CPU mais preciso
            cpu_percent=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}' 2>/dev/null || echo "0")
        else
            # Fallback para top com parsing melhorado
            local cpu_line=$(top -bn1 | grep "Cpu(s)" 2>/dev/null || echo "")
            if [ -n "$cpu_line" ]; then
                # Extrair apenas o valor numérico do uso de CPU
                cpu_percent=$(echo "$cpu_line" | sed 's/.*, *\([0-9.]*\)%id.*/\1/' | awk '{print 100-$1}' 2>/dev/null || echo "0")
            fi
        fi
        
        # Validar e limitar CPU entre 0-100
        cpu_percent=$(echo "$cpu_percent" | sed 's/[^0-9.]//g')
        if [ -z "$cpu_percent" ] || [ "$cpu_percent" = "" ]; then
            cpu_percent=0
        fi
        # Limitar a 100% máximo
        if (( $(echo "$cpu_percent > 100" | bc -l) )); then
            cpu_percent=100
        fi
        
        # Swap (formato português: Swap:)
        local swap_info=$(free -m | grep '^Swap:')
        local swap_used=$(echo "$swap_info" | awk '{print $3}' 2>/dev/null || echo "0")
        local swap_total=$(echo "$swap_info" | awk '{print $2}' 2>/dev/null || echo "0")
        local swap_percent=0
        if [ "$swap_total" -gt 0 ]; then
            swap_percent=$((swap_used * 100 / swap_total))
        fi
        
        # Disco - usar iostat se disponível, senão usar /proc/diskstats
        local disk_read=0
        local disk_write=0
        
        if command -v iostat &> /dev/null; then
            # Usar iostat para obter dados de disco em tempo real
            local disk_stats=$(iostat -x 1 1 2>/dev/null | grep -E "^(sda|nvme|mmcblk)" | head -1)
            if [ -n "$disk_stats" ]; then
                disk_read=$(echo "$disk_stats" | awk '{print $4}' 2>/dev/null || echo "0")
                disk_write=$(echo "$disk_stats" | awk '{print $5}' 2>/dev/null || echo "0")
                # Converter de KB/s para KB/s (já está na unidade correta)
            fi
        else
            # Fallback para /proc/diskstats (valores acumulados)
            local disk_stats=$(cat /proc/diskstats | grep -E "(sda|nvme|mmcblk)" | head -1)
            if [ -n "$disk_stats" ]; then
                # Valores são em setores de 512 bytes, converter para KB
                local sectors_read=$(echo "$disk_stats" | awk '{print $6}' 2>/dev/null || echo "0")
                local sectors_write=$(echo "$disk_stats" | awk '{print $10}' 2>/dev/null || echo "0")
                local current_disk_read=$((sectors_read * 512 / 1024))
                local current_disk_write=$((sectors_write * 512 / 1024))
                
                # Calcular delta se não for primeira medição
                if [ "$is_first" != "true" ]; then
                    disk_read=$((current_disk_read - prev_disk_r))
                    disk_write=$((current_disk_write - prev_disk_w))
                    # Garantir valores não negativos
                    if [ "$disk_read" -lt 0 ]; then disk_read=0; fi
                    if [ "$disk_write" -lt 0 ]; then disk_write=0; fi
                fi
            fi
        fi
        
        # Rede - detectar interface ativa automaticamente
        local network_rx=0
        local network_tx=0
        
        # Lista de interfaces comuns para verificar
        local interfaces=("eth0" "enp0s3" "enp0s8" "wlan0" "wlp" "enp" "eth")
        
        for interface in "${interfaces[@]}"; do
            local network_info=$(cat /proc/net/dev | grep "$interface" | head -1)
            if [ -n "$network_info" ]; then
                local current_rx=$(echo "$network_info" | awk '{print $2}' 2>/dev/null || echo "0")
                local current_tx=$(echo "$network_info" | awk '{print $10}' 2>/dev/null || echo "0")
                
                # Calcular delta se não for primeira medição
                if [ "$is_first" != "true" ]; then
                    network_rx=$((current_rx - prev_rx))
                    network_tx=$((current_tx - prev_tx))
                    # Garantir valores não negativos
                    if [ "$network_rx" -lt 0 ]; then network_rx=0; fi
                    if [ "$network_tx" -lt 0 ]; then network_tx=0; fi
                fi
                break
            fi
        done
        
        # Se não encontrou interface específica, pegar a primeira ativa
        if [ "$network_rx" = "0" ] && [ "$network_tx" = "0" ]; then
            local network_info=$(cat /proc/net/dev | grep -v "lo:" | grep ":" | head -1)
            if [ -n "$network_info" ]; then
                local current_rx=$(echo "$network_info" | awk '{print $2}' 2>/dev/null || echo "0")
                local current_tx=$(echo "$network_info" | awk '{print $10}' 2>/dev/null || echo "0")
                
                # Calcular delta se não for primeira medição
                if [ "$is_first" != "true" ]; then
                    network_rx=$((current_rx - prev_rx))
                    network_tx=$((current_tx - prev_tx))
                    # Garantir valores não negativos
                    if [ "$network_rx" -lt 0 ]; then network_rx=0; fi
                    if [ "$network_tx" -lt 0 ]; then network_tx=0; fi
                fi
            fi
        fi
        
        echo "$memory_used:$memory_total:$memory_percent:$cpu_percent:$swap_used:$swap_total:$swap_percent:$disk_read:$disk_write:$network_rx:$network_tx"
    }
    
    # Função para atualizar valores máximos
    update_maximums() {
        local metrics="$1"
        IFS=':' read -r mem_used mem_total mem_percent cpu_percent swap_used swap_total swap_percent disk_read disk_write net_rx net_tx <<< "$metrics"
        
        # Validar e converter para números
        mem_used=$(echo "$mem_used" | sed 's/[^0-9]//g')
        cpu_percent=$(echo "$cpu_percent" | sed 's/[^0-9.]//g')
        swap_used=$(echo "$swap_used" | sed 's/[^0-9]//g')
        disk_read=$(echo "$disk_read" | sed 's/[^0-9.]//g')
        disk_write=$(echo "$disk_write" | sed 's/[^0-9.]//g')
        net_rx=$(echo "$net_rx" | sed 's/[^0-9]//g')
        net_tx=$(echo "$net_tx" | sed 's/[^0-9]//g')
        
        # Definir valores padrão se vazios
        mem_used=${mem_used:-0}
        cpu_percent=${cpu_percent:-0}
        swap_used=${swap_used:-0}
        disk_read=${disk_read:-0}
        disk_write=${disk_write:-0}
        net_rx=${net_rx:-0}
        net_tx=${net_tx:-0}
        
        # Atualizar máximos
        if [ "$mem_used" -gt "$max_memory" ] 2>/dev/null; then
            max_memory=$mem_used
        fi
        if [ "$cpu_percent" -gt "$max_cpu" ] 2>/dev/null; then
            max_cpu=$cpu_percent
        fi
        if [ "$swap_used" -gt "$max_swap" ] 2>/dev/null; then
            max_swap=$swap_used
        fi
        if [ "$disk_read" -gt "$max_disk_read" ] 2>/dev/null; then
            max_disk_read=$disk_read
        fi
        if [ "$disk_write" -gt "$max_disk_write" ] 2>/dev/null; then
            max_disk_write=$disk_write
        fi
        if [ "$net_rx" -gt "$max_network_rx" ] 2>/dev/null; then
            max_network_rx=$net_rx
        fi
        if [ "$net_tx" -gt "$max_network_tx" ] 2>/dev/null; then
            max_network_tx=$net_tx
        fi
    }
    
    # Função para mostrar informações em tempo real
    show_realtime_display() {
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local hours=$((elapsed / 3600))
        local minutes=$(((elapsed % 3600) / 60))
        local seconds=$((elapsed % 60))
        
        local time_str=""
        if [ $hours -gt 0 ]; then
            time_str="${hours}h ${minutes}m ${seconds}s"
        elif [ $minutes -gt 0 ]; then
            time_str="${minutes}m ${seconds}s"
        else
            time_str="${seconds}s"
        fi
        
        # Obter métricas atuais
        local current_metrics=$(get_current_metrics "$prev_network_rx" "$prev_network_tx" "$prev_disk_read" "$prev_disk_write" "$first_measurement")
        update_maximums "$current_metrics"
        
        IFS=':' read -r mem_used mem_total mem_percent cpu_percent swap_used swap_total swap_percent disk_read disk_write net_rx net_tx <<< "$current_metrics"
        
        # Atualizar valores anteriores para próxima medição
        if [ "$first_measurement" = "true" ]; then
            first_measurement=false
        fi
        
        # Atualizar valores de rede e disco para cálculo de delta
        if [ "$net_rx" -gt 0 ] || [ "$net_tx" -gt 0 ]; then
            prev_network_rx=$net_rx
            prev_network_tx=$net_tx
        fi
        if [ "$disk_read" -gt 0 ] || [ "$disk_write" -gt 0 ]; then
            prev_disk_read=$disk_read
            prev_disk_write=$disk_write
        fi
        
        # Limpar tela e mostrar informações
        clear
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
        echo "║                📈 WORKER BOSS - MONITOR DE PERFORMANCE 📈                ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
        echo "⏱️  Tempo de monitoramento: $time_str"
    echo ""
        echo "🧠 MEMÓRIA RAM"
        echo "   • Uso atual: ${mem_used} MB ($(convert_mb_to_gb $mem_used)) (${mem_percent}%)"
        echo "   • Pico máximo: $max_memory MB ($(convert_mb_to_gb $max_memory))"
        echo "   • Total disponível: ${mem_total} MB ($(convert_mb_to_gb $mem_total))"
    echo ""
        echo "⚡ CPU"
        echo "   • Uso atual: ${cpu_percent}%"
        echo "   • Pico máximo: $max_cpu%"
    echo ""
        echo "💾 SWAP"
        echo "   • Uso atual: ${swap_used} MB ($(convert_mb_to_gb $swap_used)) (${swap_percent}%)"
        echo "   • Pico máximo: $max_swap MB ($(convert_mb_to_gb $max_swap))"
        echo "   • Total disponível: ${swap_total} MB ($(convert_mb_to_gb $swap_total))"
    echo ""
        echo "💿 DISCO"
        echo "   • Leitura atual: ${disk_read} KB/s"
        echo "   • Escrita atual: ${disk_write} KB/s"
        echo "   • Leitura máxima: $max_disk_read KB/s"
        echo "   • Escrita máxima: $max_disk_write KB/s"
    echo ""
        echo "🌐 REDE"
        echo "   • Recebido atual: ${net_rx} bytes/s"
        echo "   • Enviado atual: ${net_tx} bytes/s"
        echo "   • Recebido máximo: $max_network_rx bytes/s"
        echo "   • Enviado máximo: $max_network_tx bytes/s"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
        echo "║  Pressione Ctrl+C para finalizar e ver os resultados finais          ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
}

    # Variável de controle para o loop
    local continue_monitoring=true
    
    # Loop principal de monitoramento
    while [ "$continue_monitoring" = true ]; do
        show_realtime_display
        sleep 1
    done
}

# Função para mostrar informações do sistema (versão estática)
show_system_info() {
    # Informações básicas do sistema
    local os_info=$(lsb_release -d 2>/dev/null | cut -f2)
    local kernel=$(uname -r)
    local python_version=$(python3 --version 2>/dev/null || echo "Não instalado")
    local git_version=$(git --version 2>/dev/null || echo "Não instalado")
    
    # Informações do usuário
    local current_user=$(whoami)
    local user_home=$(echo $HOME)
    
    # Informações do Docker
    local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo "Não instalado")
    local docker_compose_version=$(docker compose version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' | head -1 || echo "Não instalado")
    
    # Informações do PHP
    local php_version=$(php --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "Não instalado")
    
    # Informações do Git atual
    local git_user_name=$(git config --global user.name 2>/dev/null || echo "Não configurado")
    local git_user_email=$(git config --global user.email 2>/dev/null || echo "Não configurado")
    
    # Informações de hardware
    local cpu_name=$(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d':' -f2 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "Não disponível")
    local cpu_cores=$(nproc 2>/dev/null || echo "Não disponível")
    local total_memory=$(free -h | grep "Mem.:" | awk '{print $2}' 2>/dev/null || echo "Não disponível")
    local used_memory=$(free -h | grep "Mem.:" | awk '{print $3}' 2>/dev/null || echo "Não disponível")
    
    # Informações da placa de vídeo
    local gpu_info=""
    local gpu_memory_total=""
    local gpu_memory_used=""
    
    # Tentar detectar GPU dedicada (NVIDIA)
    if command -v nvidia-smi &> /dev/null; then
        gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "")
        if [ -n "$gpu_info" ]; then
            gpu_info="NVIDIA $gpu_info"
            
            # Obter informações de memória da GPU NVIDIA
            local gpu_mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "")
            local gpu_mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "")
            
            if [ -n "$gpu_mem_total" ] && [ -n "$gpu_mem_used" ]; then
                # Converter de MB para GB
                local gpu_mem_total_gb=$((gpu_mem_total / 1024))
                local gpu_mem_used_gb=$((gpu_mem_used / 1024))
                gpu_memory_total="${gpu_mem_total_gb}GB"
                gpu_memory_used="${gpu_mem_used_gb}GB"
            fi
        fi
    fi
    
    # Se não encontrou NVIDIA, tentar AMD
    if [ -z "$gpu_info" ] && command -v rocm-smi &> /dev/null; then
        gpu_info=$(rocm-smi --showproductname 2>/dev/null | grep "Card series" | cut -d':' -f2 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "")
        if [ -n "$gpu_info" ]; then
            gpu_info="AMD $gpu_info"
            
            # Obter informações de memória da GPU AMD
            local gpu_mem_info=$(rocm-smi --showmeminfo vram 2>/dev/null | grep -E "Total|Used" | head -2)
            if [ -n "$gpu_mem_info" ]; then
                gpu_memory_total=$(echo "$gpu_mem_info" | grep "Total" | awk '{print $2}' | sed 's/MB//' 2>/dev/null || echo "")
                gpu_memory_used=$(echo "$gpu_mem_info" | grep "Used" | awk '{print $2}' | sed 's/MB//' 2>/dev/null || echo "")
                
                if [ -n "$gpu_memory_total" ] && [ -n "$gpu_memory_used" ]; then
                    # Converter de MB para GB
                    local gpu_mem_total_gb=$((gpu_memory_total / 1024))
                    local gpu_mem_used_gb=$((gpu_memory_used / 1024))
                    gpu_memory_total="${gpu_mem_total_gb}GB"
                    gpu_memory_used="${gpu_mem_used_gb}GB"
                fi
            fi
        fi
    fi
    
    # Se não encontrou GPU dedicada, tentar detectar GPU integrada via lspci
    if [ -z "$gpu_info" ]; then
        gpu_info=$(lspci | grep -i "vga\|3d\|display" | head -1 | cut -d':' -f3 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "")
        if [ -n "$gpu_info" ]; then
            # Detectar se é Intel, AMD ou NVIDIA integrada
            if echo "$gpu_info" | grep -qi "intel"; then
                gpu_info="Intel $gpu_info"
            elif echo "$gpu_info" | grep -qi "amd\|ati"; then
                gpu_info="AMD $gpu_info"
            elif echo "$gpu_info" | grep -qi "nvidia"; then
                gpu_info="NVIDIA $gpu_info"
            fi
            
            # Para GPUs integradas, tentar obter informações de memória compartilhada
            if [ -z "$gpu_memory_total" ]; then
                # Tentar via lshw para obter informações de memória
                local gpu_mem_info=$(lshw -c display 2>/dev/null | grep -i "size\|memory" | head -1)
                if [ -n "$gpu_mem_info" ]; then
                    gpu_memory_total=$(echo "$gpu_mem_info" | awk '{print $2}' 2>/dev/null || echo "")
                    if [ -n "$gpu_memory_total" ]; then
                        gpu_memory_total="~${gpu_memory_total} (compartilhada)"
                    fi
                fi
            fi
        fi
    fi
    
    # Se ainda não encontrou, tentar via lshw
    if [ -z "$gpu_info" ]; then
        gpu_info=$(lshw -c display 2>/dev/null | grep "product:" | head -1 | cut -d':' -f2 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "")
    fi
    
    # Fallback final
    if [ -z "$gpu_info" ]; then
        gpu_info="Não detectada"
    fi
    
    # Fallback para memória da GPU
    if [ -z "$gpu_memory_total" ]; then
        gpu_memory_total="Não disponível"
    fi
    if [ -z "$gpu_memory_used" ]; then
        gpu_memory_used="Não disponível"
    fi
    
    # Temperatura da CPU (se disponível)
    local cpu_temp=""
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        local temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [ -n "$temp_raw" ]; then
            local temp_celsius=$((temp_raw / 1000))
            cpu_temp="${temp_celsius}°C"
        else
            cpu_temp="Não disponível"
        fi
    else
        cpu_temp="Não disponível"
    fi
    
    # Temperatura da GPU (se disponível)
    local gpu_temp=""
    
    # Tentar obter temperatura da GPU NVIDIA
    if command -v nvidia-smi &> /dev/null; then
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' 2>/dev/null || echo "")
        if [ -n "$gpu_temp" ]; then
            gpu_temp="${gpu_temp}°C"
        fi
    fi
    
    # Tentar obter temperatura da GPU AMD
    if [ -z "$gpu_temp" ] && command -v rocm-smi &> /dev/null; then
        gpu_temp=$(rocm-smi --showtemp 2>/dev/null | grep "Temperature" | awk '{print $2}' | sed 's/C//' 2>/dev/null || echo "")
        if [ -n "$gpu_temp" ]; then
            gpu_temp="${gpu_temp}°C"
        fi
    fi
    
    # Tentar obter temperatura via sensors (lm-sensors)
    if [ -z "$gpu_temp" ] && command -v sensors &> /dev/null; then
        gpu_temp=$(sensors 2>/dev/null | grep -i "gpu\|vga\|radeon\|nvidia" | grep -i "temp" | head -1 | grep -o '[0-9]*\.[0-9]*°C' | head -1 || echo "")
    fi
    
    # Fallback para temperatura da GPU
    if [ -z "$gpu_temp" ]; then
        gpu_temp="Não disponível"
    fi
    
    # Construir mensagem de informações
    local info_message="💻 INFORMAÇÕES DO SISTEMA\n\n"
    info_message+="🖥️  SISTEMA OPERACIONAL\n\n"
    info_message+="• SO: $os_info\n"
    info_message+="• Kernel: $kernel\n"
    info_message+="• Usuário: $current_user\n"
    info_message+="• Home: $user_home\n\n"
    
    info_message+="🔧 FERRAMENTAS DE DESENVOLVIMENTO\n\n"
    info_message+="• Python: $python_version\n"
    info_message+="• Git: $git_version\n"
    info_message+="• Docker: $docker_version\n"
    info_message+="• Docker Compose: $docker_compose_version\n"
    info_message+="• PHP: $php_version\n\n"
    
    info_message+="👤 CONFIGURAÇÃO GIT\n\n"
    info_message+="• Nome: $git_user_name\n"
    info_message+="• Email: $git_user_email\n\n"
    
    info_message+="🖥️  PROCESSADOR (CPU)\n\n"
    info_message+="• Modelo: $cpu_name\n"
    info_message+="• Núcleos: $cpu_cores\n"
    info_message+="• Temperatura: $cpu_temp\n\n"
    
    info_message+="🎮 PLACA DE VÍDEO (GPU)\n\n"
    info_message+="• Modelo: $gpu_info\n"
    info_message+="• VRAM Total: $gpu_memory_total\n"
    info_message+="• VRAM Usada: $gpu_memory_used\n"
    info_message+="• Temperatura: $gpu_temp\n\n"
    
    info_message+="💾 MEMÓRIA RAM\n\n"
    info_message+="• Total: $total_memory\n"
    info_message+="• Usada: $used_memory\n\n"
    
    info_message+="🚀 WORKER BOSS v2.0\n"
    info_message+="Interface Whiptail"
    
    whiptail --title "💻 Informações do Sistema" \
              --scrolltext \
              --msgbox "$info_message" \
              25 80
}


# Abre um ficheiro no editor: VISUAL → EDITOR → git core.editor → nano (eval para comandos com argumentos).
_zshmap_edit_file_interactive() {
    local f="$1"
    local cmd=""
    [ -n "${VISUAL:-}" ] && cmd="$VISUAL"
    [ -z "$cmd" ] && [ -n "${EDITOR:-}" ] && cmd="$EDITOR"
    [ -z "$cmd" ] && cmd=$(git config --global core.editor 2>/dev/null || true)
    [ -z "$cmd" ] && cmd="nano"
    clear 2>/dev/null || true
    echo "Abrindo com: $cmd"
    echo "Ficheiro: $f"
    echo "(Feche o editor para voltar ao ZshMap.)"
    echo ""
    eval "$cmd $(printf '%q' "$f")"
}

# Cria ~/.zshmap.yml se não existir, mostra resumo Git e abre o YAML no editor.
execute_zshmap_home_config_setup() {
    local wb_script_dir wb_home wb_example created
    wb_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    wb_home="$HOME/.zshmap.yml"
    wb_example="$wb_script_dir/.zshmap.home.example.yml"
    created=0
    
    if [ ! -f "$wb_home" ]; then
        if [ -f "$wb_example" ]; then
            if ! cp "$wb_example" "$wb_home" 2>/dev/null; then
                whiptail --title "❌ Erro" \
                         --msgbox "Não foi possível criar ~/.zshmap.yml (cópia falhou).\n\nVerifique permissões na sua home." \
                         10 62
                return 1
            fi
        else
            if ! cat > "$wb_home" <<'WBHOMEYAML'
projects:
  dir: "~/Projects"
  ignore_dirs: []

# Scripts de instalação (.sh por SO, ex.: ubuntu/) — install.programs_dir é sempre uma lista.
install:
  programs_dir:
    - "~/Projects/substitui-pelo-repo/programs"
    - "~/Projects/substitui-pelo-repo/outros-programs"

shell:
  extras_source:
    - "~/Projects/substitui-pelo-repo/.zshmap-extras.zsh"
WBHOMEYAML
            then
                whiptail --title "❌ Erro" \
                         --msgbox "Não foi possível criar ~/.zshmap.yml." \
                         8 60
                return 1
            fi
        fi
        created=1
    fi
    
    local gn ge gc
    gn=$(git config --global user.name 2>/dev/null || echo "Não configurado")
    ge=$(git config --global user.email 2>/dev/null || echo "Não configurado")
    gc=$(git config --global core.editor 2>/dev/null || echo "Não configurado")
    
    local status_line
    if [ "$created" -eq 1 ]; then
        status_line="✅ Foi criado ~/.zshmap.yml (modelo do ZshMap)."
    else
        status_line="ℹ️  O ficheiro ~/.zshmap.yml já existe — não foi alterado."
    fi
    
    whiptail --title "⚙️ Configuração ZshMap" \
             --msgbox "${status_line}

📋 Configurações atuais do Git:

👤 Nome: ${gn}
📧 Email: ${ge}
✏️  Editor: ${gc}

A seguir o ficheiro abre no editor acima (ou nano se nada estiver definido).
Feche o editor para voltar ao menu." \
             24 74
    
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        _zshmap_edit_file_interactive "$wb_home" </dev/tty >/dev/tty 2>&1
    else
        whiptail --title "⚠️ Sem terminal interativo" \
                 --msgbox "Não foi possível abrir o editor automaticamente.\n\nEdite manualmente:\n$wb_home" \
                 12 64
    fi
}

# Função para mostrar menu principal (tags estáveis: prog só aparece se houver scripts .sh no diretório configurado)
show_main_menu() {
    local -a entries=()
    local menu_height total_h choice
    
    if _zshmap_programs_has_any_sh; then
        entries+=("prog" "📦 Instalação de Programas")
    fi
    entries+=("yaml" "⚡ Atalhos Dinâmicos (YAML)")
    entries+=("zpa" "🔧 Gerar .zprofile-auto")
    entries+=("dup" "🔍 Validar Atalhos Duplicados")
    entries+=("cst" "🔧 Atalhos Customizados")
    entries+=("git" "📚 Configuração Git Local")
    entries+=("zsh" "🐚 Dependências do ZSH")
    entries+=("sys" "💻 Informações do Sistema")
    entries+=("cfg" "⚙️ Configurar ~/.zshmap.yml (start)")
    entries+=("quit" "🚪 Sair")
    
    menu_height=$((${#entries[@]} / 2))
    [ "$menu_height" -gt 14 ] && menu_height=14
    total_h=$((menu_height + 8))
    [ "$total_h" -lt 22 ] && total_h=22
    
    choice=$(whiptail --title "🚀 ZshMap - Menu Principal" \
                      --menu "Escolha uma opção:" \
                      "$total_h" 70 "$menu_height" \
                      "${entries[@]}" \
                      3>&1 1>&2 2>&3)
    
    echo "$choice"
}

# Função para mostrar confirmação de saída
confirm_exit() {
    whiptail --title "🚪 Confirmar Saída" \
              --yesno "Tem certeza que deseja sair do ZshMap?\n\nTodas as operações em andamento serão canceladas." \
              10 60
    
    return $?
}

# Encerra o shell que lançou este script (ex.: zsh ao rodar zsh-map-exec).
# Só "exit" no bash filho devolve o prompt no zsh — a aba do terminal não fecha.
_zshmap_terminate_parent_shell_if_interactive() {
    local ppid="${PPID:-}"
    [ -n "$ppid" ] && [ "$ppid" -gt 1 ] || return 0
    local pcomm
    pcomm=$(ps -o comm= -p "$ppid" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$pcomm" ] || return 0
    case "$pcomm" in
        zsh|-zsh|bash|-bash) ;;
        *) return 0 ;;
    esac
    kill -TERM "$ppid" 2>/dev/null || true
}

# Função principal
main() {
    # Verificar se foi chamado apenas para carregar funções
    if [ "$1" = "--functions-only" ]; then
        # Apenas carregar as funções, não executar o menu principal
        return 0
    fi
    
    # Verificar se whiptail está instalado
    check_whiptail
    
    # Mostrar tela de boas-vindas
    show_welcome
    
    local running=true
    
    while [ "$running" = true ]; do
        local choice=$(show_main_menu)
        
        case $choice in
            prog)
                execute_programs
                ;;
            yaml)
                execute_dynamic_shortcuts
                ;;
            zpa)
                # Obrigatório: mesma validação do menu «Validar Atalhos Duplicados». Com duplicatas, não gera arquivo.
                whiptail --title "🔍 Antes de gerar .zprofile-auto" \
                         --msgbox "Será executada a verificação de atalhos duplicados entre projetos.\n\nA lista detalhada aparece no terminal (atrás desta janela ou na sessão onde o ZshMap foi iniciado)." \
                         12 62
                
                validate_duplicate_shortcuts
                local dup_check_rc=$?
                
                if [ "$dup_check_rc" -eq 1 ]; then
                    echo ""
                    echo "────────────────────────────────────────────────────────────"
                    if [ -r /dev/tty ]; then
                        read -r -p "Pressione Enter no terminal para ver o aviso..." _ </dev/tty
                    else
                        read -r -p "Pressione Enter para continuar..." _
                    fi
                    whiptail --title "❌ Geração bloqueada" \
                             --scrolltext \
                             --msgbox "Foram encontrados atalhos duplicados entre projetos.\n\nO arquivo .zprofile-auto NÃO será gerado: cada nome de atalho precisa ser único entre todos os zshmap.yml dos projetos.\n\nConsulte o terminal para a lista (nome do atalho e pastas de projeto)." \
                             14 68
                else
                    # Gerar .zprofile-auto com loader simples
                    {
                        echo "0"
                        echo "Iniciando geração do .zprofile-auto..."
                        sleep 0.3
                        echo "50"
                        echo "Processando projetos e gerando atalhos..."
                        sleep 0.3
                        echo "100"
                        echo "Finalizando arquivo..."
                    } | whiptail --title "🔧 Gerando .zprofile-auto" \
                                 --gauge "Gerando arquivo .zprofile-auto a partir dos projetos..." \
                                 8 60 0
                    
                    if generate_zprofile_auto; then
                        # Encerrar o shell após OK: assim o próximo terminal carrega ~/.zprofile-auto pelo .zshrc
                        # (melhor que pedir ao usuário para rodar source manualmente nesta sessão).
                        local z_done_msg=""
                        z_done_msg=$(printf '%s\n' \
                            "✅ Arquivo ~/.zprofile-auto foi gerado com sucesso." \
                            "" \
                            "Este shell ainda pode ter a versão ANTIGA das funções em memória." \
                            "Os atalhos novos/atualizados entram quando o arquivo é carregado de novo pelo Zsh (abrindo um terminal novo)." \
                            "" \
                            "Ao pressionar <Ok>, o shell que abriu o ZshMap (ex.: esta aba no zsh) será encerrado." \
                            "Abra um terminal novo para carregar ~/.zprofile-auto e usar os atalhos atualizados.")
                        whiptail --title "✅ .zprofile-auto pronto" \
                                 --scrolltext \
                                 --msgbox "$z_done_msg" \
                                 18 72
                        _zshmap_terminate_parent_shell_if_interactive
                        exit 0
                    else
                        whiptail --title "❌ Erro" \
                                 --msgbox "Erro ao gerar o arquivo .zprofile-auto!\n\nVerifique se os ficheiros zshmap.yml dos projetos estão corretos." \
                                 10 60
                    fi
                fi
                ;;
            dup)
                # Verificar atalhos duplicados (informativo)
                whiptail --title "🔍 Verificação de atalhos duplicados" \
                         --msgbox "Serão lidos os zshmap.yml dos projetos (e workerboss.yml legado, se existir).\n\nA saída completa aparece no terminal (atrás desta janela ou na sessão onde o ZshMap foi iniciado).\n\nDepois de ler o resultado no terminal, pressione Enter lá para ver o resumo na próxima tela." \
                         14 62
                
                validate_duplicate_shortcuts
                dup_status=$?
                
                echo ""
                echo "────────────────────────────────────────────────────────────"
                if [ -r /dev/tty ]; then
                    read -r -p "Pressione Enter no terminal para ver o resumo..." _ </dev/tty
                else
                    read -r -p "Pressione Enter para ver o resumo..." _
                fi
                
                if [ "$dup_status" -eq 1 ]; then
                    whiptail --title "⚠️ Verificação concluída" \
                             --msgbox "Foram encontrados atalhos duplicados entre projetos.\n\nConsulte o terminal para a lista detalhada (nome do atalho e pastas de projeto)." \
                             12 62
                else
                    whiptail --title "✅ Verificação concluída" \
                             --msgbox "Nenhum atalho duplicado foi encontrado entre os projetos." \
                             10 62
                fi
                ;;
            cst)
                execute_shortcuts
                ;;
            git)
                execute_git
                ;;
            zsh)
                execute_zsh
                ;;
            sys)
                # Mostrar opções de visualização
                local info_choice=$(whiptail --title "💻 Informações do Sistema" \
                                           --menu "Escolha o tipo de visualização:" \
                                           12 60 3 \
                                           "1" "📊 Visualização Estática" \
                                           "2" "🔄 Monitor em Tempo Real (Terminal)" \
                                           3>&1 1>&2 2>&3)
                
                case $info_choice in
                    1)
                        show_system_info
                        ;;
                    2)
                        show_system_info_realtime
                        ;;
                    *)
                        # Usuário cancelou
                        ;;
                esac
                ;;
            cfg)
                execute_zshmap_home_config_setup
                ;;
            quit)
                if confirm_exit; then
                    whiptail --title "👋 Até Logo!" \
                             --msgbox "Obrigado por usar o ZshMap!\n\nAté a próxima! 🚀" \
                             8 60
                    running=false
                fi
                ;;
            *)
                # Usuário cancelou ou fechou a janela
                if [ -z "$choice" ]; then
                    if confirm_exit; then
                        running=false
                    fi
                fi
                ;;
        esac
    done
    
    # Limpar cache ao sair normalmente
    cleanup_on_exit
}

# Função para verificar e clonar repositório se necessário
clone_repo() {
    local dir="$1"
    local repo_url="$2"
    local repo_name="${3:-$(basename "$repo_url" .git)}"
    
    # Expandir ~ no caminho
    dir="${dir/#\~/$HOME}"

    if [ ! -d "$dir" ]; then
        echo -e "\nDiretório $dir não encontrado. Clonando repositório... 🌎🌎🌎 \n"
        git clone "$repo_url" "$dir"
        if [ $? -eq 0 ]; then
            echo -e "\n✅ Repositório clonado com sucesso em $dir\n"
        else
            echo -e "\n❌ Erro ao clonar repositório $repo_url\n"
            return 1
        fi
    else
        echo -e "\nDiretório $dir já existe. Pulando clonagem... ✅✅✅ \n"
    fi
}

# Função para obter senha do banco de dados do arquivo .env
get_db_password() {
    local project_root="$1"
    local password_env_var="$2"
    
    local env_file="$project_root/.env"
    
    # Verificar se o arquivo .env existe
    if [ ! -f "$env_file" ]; then
        echo "❌ Arquivo .env não encontrado em: $env_file"
        return 1
    fi
    
    # Buscar a variável de senha no arquivo .env
    local password=$(grep "^$password_env_var=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    
    if [ -z "$password" ]; then
        echo "❌ Variável $password_env_var não encontrada no arquivo .env"
        echo "🔍 Verifique se a variável está definida corretamente no arquivo: $env_file"
        return 1
    fi
    
    echo "$password"
}

# Função para coletar parâmetros dinâmicos de dump
collect_dump_parameters() {
    local yaml_file="$1"
    local shortcut_name="$2"
    
    # Obter título do shortcut
    local shortcut_title=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .title" "$yaml_file" 2>/dev/null)
    [ "$shortcut_title" = "null" ] && shortcut_title="📝 $shortcut_name"
    local parameters=()
    
    # Verificar se o atalho tem parâmetros configurados
    local param_count=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters | length" "$yaml_file" 2>/dev/null)
    
    if [ -z "$param_count" ] || [ "$param_count" = "null" ] || [ "$param_count" = "0" ]; then
        return 0
    fi
    
    for ((i=0; i<param_count; i++)); do
        local param_name=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].name" "$yaml_file" 2>/dev/null)
        local param_type=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].type" "$yaml_file" 2>/dev/null)
        # Verificar se prompt é um array ou string
        local prompt_type=$(yq -r ".project.shortcuts[] | select(.name == "\"$shortcut_name\"") | .parameters[$i].prompt | type" "$yaml_file" 2>/dev/null)
        local param_prompt=""
        
        # Expandir variáveis do projeto no prompt
        local dump_config_bases_path=$(yq -r ".project.dump_config.bases_path" "$yaml_file" 2>/dev/null)
        [ "$dump_config_bases_path" = "null" ] && dump_config_bases_path="~/.multiplier/bases"
        dump_config_bases_path="${dump_config_bases_path/#~/$HOME}"
        
        if [ "$prompt_type" = "array" ]; then
            # Se for array, obter as linhas e substituir variáveis
            param_prompt=$(yq -r ".project.shortcuts[] | select(.name == "\"$shortcut_name\"") | .parameters[$i].prompt[]" "$yaml_file" 2>/dev/null)
            param_prompt=$(echo "$param_prompt" | sed "s|\$bases_path|$dump_config_bases_path|g")
        else
            # Se for string, usar diretamente e substituir variáveis
            param_prompt=$(yq -r ".project.shortcuts[] | select(.name == "\"$shortcut_name\"") | .parameters[$i].prompt" "$yaml_file" 2>/dev/null)
            param_prompt=$(echo "$param_prompt" | sed "s|\$bases_path|$dump_config_bases_path|g")
        fi
        local param_required=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].required" "$yaml_file" 2>/dev/null)
        local param_validation=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].validation" "$yaml_file" 2>/dev/null)
        local param_error_message=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].error_message" "$yaml_file" 2>/dev/null)
        local param_source=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].source" "$yaml_file" 2>/dev/null)
        local param_default=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .parameters[$i].default" "$yaml_file" 2>/dev/null)
        
        [ "$param_required" = "null" ] && param_required="true"
        [ "$param_validation" = "null" ] && param_validation=""
        [ "$param_error_message" = "null" ] && param_error_message="Valor inválido"
        [ "$param_source" = "null" ] && param_source=""
        [ "$param_default" = "null" ] && param_default=""
        
        local param_value=""
        local valid_input=false
        
        while [ "$valid_input" = false ]; do
            case $param_type in
                "selection")
                    # Obter opções da fonte de dados
                    local options=()
                    if [ "$param_source" = "tenants" ]; then
                        # Buscar tenants disponíveis
                        local bases_path=$(yq -r ".project.dump_config.bases_path" "$yaml_file" 2>/dev/null)
                        bases_path="${bases_path/#\~/$HOME}"
                        
                        if [ -d "$bases_path" ]; then
                            while IFS= read -r -d '' tenant_dir; do
                                local tenant=$(basename "$tenant_dir")
                                # Verificar se tem arquivos .sql.zip
                                if find "$tenant_dir" -name "*.sql.zip" -type f | grep -q .; then
                                    options+=("$tenant" "" "OFF")
                                fi
                            done < <(find "$bases_path" -maxdepth 1 -type d -not -path "$bases_path" -print0 2>/dev/null)
                        fi
                    fi
                    
                    if [ ${#options[@]} -eq 0 ]; then
                        whiptail --title "❌ Erro" \
                                 --msgbox "Nenhuma opção disponível para $param_prompt" \
                                 8 60
                        return 1
                    fi
                    
                    # Interface de seleção múltipla
                    local choices=""
                    choices=$(whiptail --title "📦 $param_prompt" \
                                            --checklist "Escolha as opções (pode selecionar múltiplos):" \
                                            15 60 8 \
                                            "${options[@]}" \
                                            3>&1 1>&2 2>&3)
                    local checklist_rc=$?
                    
                    if [ "$checklist_rc" -ne 0 ]; then
                        echo "❌ Operação cancelada pelo usuário."
                        return 1
                    fi
                    if [ -z "$choices" ]; then
                        if [ "$param_required" = "true" ]; then
                            whiptail --title "⚠️ Aviso" \
                                     --msgbox "Seleção obrigatória para $param_prompt!" \
                                     8 50
                            continue
                        else
                            param_value=""
                            valid_input=true
                        fi
                    else
                        param_value="$choices"
                        valid_input=true
                    fi
                    ;;
                    
                "input")
                    # Input de texto
                    param_value=""
                    param_value=$(whiptail --title "$shortcut_title" \
                                          --inputbox "$param_prompt:" \
                                          10 50 "$param_default" \
                                          3>&1 1>&2 2>&3)
                    
                    local dump_input_rc=$?
                    if [ "$dump_input_rc" -ne 0 ]; then
                        whiptail --title "❌ Cancelado" \
                                     --msgbox "Operação cancelada pelo usuário!" \
                                     8 50
                        return 1
                    else
                        param_value="$param_value"
                        valid_input=true
                    fi
                    if [ -z "$param_value" ] && [ "$param_required" = "true" ]; then
                        whiptail --title "⚠️ Aviso" \
                                 --msgbox "$param_prompt não pode estar vazio!" \
                                 8 50
                        continue
                    else
                        # Validar se necessário
                        if [ -n "$param_validation" ] && [ -n "$param_value" ]; then
                            if ! echo "$param_value" | grep -qE "$param_validation"; then
                                whiptail --title "❌ Erro" \
                                         --msgbox "$param_error_message" \
                                         8 50
                                continue
                            fi
                        fi
                        valid_input=true
                    fi
                    ;;
                    
                *)
                    # Tipo não suportado, usar input como fallback
                    param_value=""
                    param_value=$(whiptail --title "$shortcut_title" \
                                          --inputbox "$param_prompt:" \
                                          10 50 "$param_default" \
                                          3>&1 1>&2 2>&3)
                    
                    local dump_fb_rc=$?
                    if [ "$dump_fb_rc" -ne 0 ]; then
                        if [ "$param_required" = "true" ]; then
                            whiptail --title "⚠️ Aviso" \
                                     --msgbox "Entrada obrigatória para $param_prompt!" \
                                     8 50
                            continue
                        else
                            param_value=""
                        fi
                    fi
                    valid_input=true
                    ;;
            esac
        done
        
        parameters+=("$param_name:$param_value")
    done
    
    printf "%s|" "${parameters[@]}"
}


# Função para executar dump de banco de dados
execute_dump() {
    local project_name="$1"
    local tenant_name_from_cli="$2"
    local is_qa="$3"
    
    # Obter o caminho do arquivo YAML do projeto
    local yaml_file=$(get_project_yaml_path "$project_name")
    if [ $? -ne 0 ] || [ -z "$yaml_file" ]; then
        echo "❌ Arquivo zshmap.yml (ou workerboss.yml legado) não encontrado para o projeto $project_name!"
        return 1
    fi
    
    # Verificar se o arquivo YAML existe
    if [ ! -f "$yaml_file" ]; then
        echo "❌ Arquivo de configuração não encontrado: $yaml_file"
        return 1
    fi
    
    # Determinar o nome do atalho baseado no tipo de dump
    local shortcut_name="dump"
    if [ "$is_qa" = "true" ]; then
        shortcut_name="dump-qa"
    fi
    
    # Verificar se já temos tenant_name global (para dump-qa reutilizar do dump)
    local tenant_name=""
    if [ "$is_qa" = "true" ]; then
        # dump-qa SEMPRE usa o cache do dump anterior
        if [ -n "$GLOBAL_TENANT_NAME" ]; then
            tenant_name="$GLOBAL_TENANT_NAME"
            echo "✅ Reutilizando tenant_name do dump anterior: $tenant_name"
        else
            # Se não tem cache, verificar se tem setup_shortcut para executar dump primeiro
            local setup_shortcut=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .setup_shortcut" "$yaml_file" 2>/dev/null)
            if [ "$setup_shortcut" = "dump" ]; then
                echo "🔄 Executando dump como preparação para dump-qa..."
                # Executar o dump completo (com suas dependências) apenas uma vez
                execute_shortcut "$project_name" "dump"
                if [ $? -ne 0 ]; then
                    echo "❌ Falha na execução do dump como preparação"
                    return 1
                fi
                # Agora usar o cache que foi criado
                if [ -n "$GLOBAL_TENANT_NAME" ]; then
                    tenant_name="$GLOBAL_TENANT_NAME"
                    echo "✅ Usando tenant_name do dump executado: $tenant_name"
                else
                    echo "❌ dump-qa requer que o comando dump seja executado primeiro"
                    return 1
                fi
                echo "✅ Usando tenant_name do dump executado: $tenant_name"
            else
                echo "❌ dump-qa requer que o comando dump seja executado primeiro"
                return 1
            fi
        fi
    elif [ -z "$tenant_name_from_cli" ] || [ "$tenant_name_from_cli" = "" ]; then
        # Verificar se o atalho tem parâmetros configurados
        local param_count=$(yq -r ".project.shortcuts[] | select(.name == "$shortcut_name") | .parameters | length" "$yaml_file" 2>/dev/null)
        
        if [ -z "$param_count" ] || [ "$param_count" = "null" ] || [ "$param_count" = "0" ]; then
            # Se não tem parâmetros, usar tenant_name global se disponível
            if [ -n "$GLOBAL_TENANT_NAME" ]; then
                tenant_name="$GLOBAL_TENANT_NAME"
                echo "✅ Usando tenant_name global (sem parâmetros): $tenant_name"
            else
                # Se não tem cache, usar Whiptail para pedir o tenant_name
                echo "ℹ️ Nenhum tenant_name em cache. Abrindo interface..."
                tenant_name=""
                tenant_name=$(whiptail --title "🧪 Dump QA de Tenant" --inputbox "Os arquivos de dump devem estar na pasta $HOME/.multiplier/bases

Nome do tenant:" 10 60 3>&1 1>&2 2>&3)
                local tn_rc=$?
                if [ "$tn_rc" -ne 0 ] || [ -z "$tenant_name" ]; then
                    echo "❌ Nome do tenant não fornecido ou cancelado"
                    return 1
                fi
            fi
        else
        local dynamic_parameters=""
        dynamic_parameters=$(collect_dump_parameters "$yaml_file" "$shortcut_name")
        local dp_rc=$?
        if [ "$dp_rc" -ne 0 ]; then
            echo "❌ Falha ao coletar parâmetros dinâmicos"
            return 1
        fi
        
        # Processar parâmetros dinâmicos
        if [ -n "$dynamic_parameters" ]; then
            IFS="|" read -r PARAMS <<< "$dynamic_parameters"
            for param in $PARAMS; do
                if [ -n "$param" ]; then
                    local param_name=$(echo "$param" | cut -d":" -f1)
                    local param_value=$(echo "$param" | cut -d":" -f2-)
                    
                    if [ "$param_name" = "tenant_name" ] && [ -n "$param_value" ]; then
                        tenant_name=$(echo "$param_value" | tr -d "|")
                    fi
                fi
            done
        fi
        fi
    else
        tenant_name="$tenant_name_from_cli"
    fi
    
    if [ -z "$tenant_name" ]; then
        echo "❌ Nome do tenant não fornecido ou cancelado."
        return 1
    fi
    
    # Salvar tenant_name na variável global se for dump (não dump-qa)
    if [ "$is_qa" = "false" ]; then
        GLOBAL_TENANT_NAME="$tenant_name"
        echo "💾 Salvando tenant_name para reutilização: $tenant_name"
    fi
    
    # Obter configurações do projeto
    local project_root=$(yq -r ".project.root" "$yaml_file" 2>/dev/null)
    
    # Expandir ~ no caminho
    project_root="${project_root/#\~/$HOME}"
    
    # Navegar para o diretório do projeto
    cd "$project_root" || { echo "❌ Não foi possível navegar para o diretório do projeto: $project_root"; return 1; }
    
    # Obter comandos do atalho
    local commands=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .commands[]" "$yaml_file" 2>/dev/null)
    
    # Construir script com substituição de variáveis
    local script_content=""
    while IFS= read -r command; do
        if [ -n "$command" ]; then
            # Substituir variáveis no comando
            command=$(echo "$command" | sed "s/\$tenant_name/$tenant_name/g")
            script_content="$script_content
$command"
        fi
    done <<< "$commands"
    
    # Verificar se deve mostrar saída detalhada
    local show_output=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .show_output" "$yaml_file" 2>/dev/null)
    
    if [ "$show_output" = "true" ]; then
        # Mostrar saída detalhada com pausa no final
        clear
        echo "⚡ Executando script de dump..."
        echo ""
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        echo "$script_content" | bash
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo ""
            echo "════════════════════════════════════════════════════════════════"
            echo "❌ Falha na execução do script (código: $exit_code)"
            echo "════════════════════════════════════════════════════════════════"
            echo ""
            echo "Pressione Enter para continuar..."
            read -r
            return $exit_code
        fi
        echo ""
        echo "════════════════════════════════════════════════════════════════"
        echo "✅ Dump executado com sucesso!"
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        echo "Pressione Enter para continuar..."
        read -r
    else
        # Execução normal sem pausa
        echo "⚡ Executando script de dump..."
        echo "$script_content" | bash
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo "❌ Falha na execução do script (código: $exit_code)"
            return $exit_code
        fi
        echo "✅ Dump executado com sucesso!"
    fi
    
    return 0

}

# Formata corpo de diálogo do wizard de testes: contexto da etapa em cima, pergunta embaixo.
_zshmap_it_step_body() {
    local step_no="$1"
    local step_total="$2"
    local stage_heading="$3"
    local stage_extra="$4"
    local question_text="$5"
    local sep="────────────────────────────────────────"
    local top=""
    top=$(printf 'Etapa %s de %s\n%s' "$step_no" "$step_total" "$stage_heading")
    if [ -n "$stage_extra" ] && [ "$stage_extra" != "null" ]; then
        top=$(printf '%s\n\n%s' "$top" "$stage_extra")
    fi
    printf '%s\n\n%s\n\n%s' "$top" "$sep" "$question_text"
}

# Whiptail com stdin no TTY real (Voltar/Cancel/ESC confiáveis em terminais integrados).
_zshmap_it_whiptail_plain() {
    if [ -c /dev/tty ] && [ -r /dev/tty ]; then
        whiptail "$@" </dev/tty
    else
        whiptail "$@"
    fi
}

# Menu/input: padrão 3>&1 1>&2 2>&3 + stdin no TTY.
_zshmap_it_whiptail_fancy() {
    if [ -c /dev/tty ] && [ -r /dev/tty ]; then
        whiptail "$@" 3>&1 1>&2 2>&3 </dev/tty
    else
        whiptail "$@" 3>&1 1>&2 2>&3
    fi
}

# Ordem real de atalhos quando há setup_shortcut em cadeia (pré-requisitos primeiro).
_zshmap_it_ordered_setup_chain() {
    local yaml_file="$1"
    local shortcut_name="$2"
    local depth="${3:-0}"
    if [ "$depth" -gt 20 ]; then
        return 0
    fi
    local setup_sc
    setup_sc=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .setup_shortcut" "$yaml_file" 2>/dev/null)
    if [ "$setup_sc" != "null" ] && [ -n "$setup_sc" ]; then
        _zshmap_it_ordered_setup_chain "$yaml_file" "$setup_sc" $((depth + 1))
    fi
    printf '%s\n' "$shortcut_name"
}

_zshmap_it_commands_lines_for_shortcut() {
    local yaml_file="$1"
    local sc="$2"
    local n=0
    if yq -e ".project.shortcuts[] | select(.name == \"$sc\") | .commands" "$yaml_file" >/dev/null 2>&1; then
        while IFS= read -r cmdline; do
            [ -z "$cmdline" ] && continue
            n=$((n + 1))
            printf '      %2d) %s\n' "$n" "$cmdline"
        done < <(yq -r ".project.shortcuts[] | select(.name == \"$sc\") | .commands[]" "$yaml_file" 2>/dev/null)
        [ "$n" -eq 0 ] && printf '      (array commands vazio no YAML)\n'
        return 0
    fi
    local one
    one=$(yq -r ".project.shortcuts[] | select(.name == \"$sc\") | .command" "$yaml_file" 2>/dev/null)
    if [ "$one" != "null" ] && [ -n "$one" ]; then
        printf '       1) %s\n' "$one"
        return 0
    fi
    local st
    st=$(yq -r ".project.shortcuts[] | select(.name == \"$sc\") | .type" "$yaml_file" 2>/dev/null)
    printf '      (sem .commands/.command fixos — type=%s; ver zshmap.yml)\n' "${st:-?}"
}

# Monta o comando final do wizard interactive-test a partir de command_line no YAML:
# 1) test_config.command_line do atalho interactive-test (sobrescreve);
# 2) project.test_config.command_line (padrão do projeto; qualquer stack).
# Sem command_line em nenhum dos dois: retorno 1 (caller mostra msgbox).
_zshmap_it_build_interactive_final_cmd() {
    local yaml_file="$1"
    local shortcut_name="$2"
    local test_command_answer="$3"
    local testsuite_answer="$4"
    local filter_answer="$5"
    local no_coverage_answer="$6"
    local tc=".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config"
    local cl=""
    
    if [ "$(yq "$tc | has(\"command_line\")" "$yaml_file" 2>/dev/null)" = "true" ]; then
        cl="$tc.command_line"
    elif [ "$(yq ".project.test_config | has(\"command_line\")" "$yaml_file" 2>/dev/null)" = "true" ]; then
        cl=".project.test_config.command_line"
    else
        echo "zsh-map: interactive-test sem command_line: defina project.test_config.command_line ou test_config.command_line no atalho «${shortcut_name}» em ${yaml_file}" >&2
        return 1
    fi
    local inc_ts ts_flag inc_f filt_flag inc_nc nc_flag nc_when
    inc_ts=$(yq -r "${cl}.include_testsuite // true" "$yaml_file" 2>/dev/null)
    ts_flag=$(yq -r "${cl}.testsuite_flag // \"--testsuite\"" "$yaml_file" 2>/dev/null)
    inc_f=$(yq -r "${cl}.include_filter_if_non_empty // true" "$yaml_file" 2>/dev/null)
    filt_flag=$(yq -r "${cl}.filter_flag // \"--filter\"" "$yaml_file" 2>/dev/null)
    inc_nc=$(yq -r "${cl}.include_no_coverage_when_sim // true" "$yaml_file" 2>/dev/null)
    nc_flag=$(yq -r "${cl}.no_coverage_flag // \"--no-coverage\"" "$yaml_file" 2>/dev/null)
    nc_when=$(yq -r "${cl}.no_coverage_answer_value // \"0\"" "$yaml_file" 2>/dev/null)
    [ "$ts_flag" = "null" ] && ts_flag=""
    [ "$filt_flag" = "null" ] && filt_flag=""
    [ "$nc_flag" = "null" ] && nc_flag=""
    [ "$nc_when" = "null" ] && nc_when="0"
    
    local fc="$test_command_answer"
    if [ "$inc_ts" = "true" ] && [ -n "$ts_flag" ]; then
        fc="$fc $ts_flag=$testsuite_answer"
    fi
    if [ "$inc_f" = "true" ] && [ -n "$filter_answer" ] && [ -n "$filt_flag" ]; then
        fc="$fc $filt_flag=$filter_answer"
    fi
    if [ "$inc_nc" = "true" ] && [ -n "$nc_flag" ] && [ "$no_coverage_answer" = "$nc_when" ]; then
        fc="$fc $nc_flag"
    fi
    
    local rules_n
    rules_n=$(yq "${cl}.color_append_rules // [] | length" "$yaml_file" 2>/dev/null)
    [ -z "$rules_n" ] || [ "$rules_n" = "null" ] && rules_n=0
    local idx=0
    while [ "$idx" -lt "$rules_n" ]; do
        local needle app
        needle=$(yq -r "${cl}.color_append_rules[$idx].contains // \"\"" "$yaml_file" 2>/dev/null)
        app=$(yq -r "${cl}.color_append_rules[$idx].append // \"\"" "$yaml_file" 2>/dev/null)
        if [ -n "$needle" ] && [ "$needle" != "null" ] && [ -n "$app" ] && [ "$app" != "null" ] && echo "$test_command_answer" | grep -qF "$needle"; then
            fc="$fc $app"
            break
        fi
        idx=$((idx + 1))
    done
    
    printf '%s' "$fc"
    return 0
}

# Função para executar testes interativos
execute_interactive_test() {
    local project_name="$1"
    local shortcut_name="$2"
    local yaml_file="$3"
    
    # Obter configurações do teste
    local recreate_env=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.recreate_environment" "$yaml_file")
    local test_commands=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.test_commands[]" "$yaml_file")
    local default_testsuite=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.default_testsuite" "$yaml_file")
    local coverage_option=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.coverage_option" "$yaml_file")
    
    # Recriação de ambiente e execução dos testes no container vêm do YAML do projeto (não fixar Multiplier)
    local setup_shortcut=$(yq -r ".project.test_config.setup_shortcut" "$yaml_file" 2>/dev/null)
    local app_container=$(yq -r ".project.docker.containers.app" "$yaml_file" 2>/dev/null)
    
    # Obter perguntas do YAML
    local questions_count
    questions_count=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions | length" "$yaml_file")
    [ -z "$questions_count" ] || [ "$questions_count" = "null" ] && questions_count=0
    
    # Variáveis para armazenar respostas (fora do loop para reutilizar)
    local recreate_env_answer=""
    local test_command_answer=""
    local testsuite_answer=""
    local filter_answer=""
    local no_coverage_answer=""
    local first_run=true
    local environment_recreated=false
    local wb_it_preview_done=false
    
    # Loop principal para permitir repetição
    while true; do
        # Só faz as perguntas na primeira execução
        if [ "$first_run" = "true" ]; then
            # Modal inicial: Continuar / Cancelar (não repetir em «rodar de novo»)
            if [ "${questions_count:-0}" -gt 0 ] 2>/dev/null; then
                local preamble_body
                preamble_body=$(printf '%s\n' \
                    "Assistente de testes interativos" \
                    "" \
                    "Projeto: ${project_name}" \
                    "Atalho:  ${shortcut_name}" \
                    "" \
                    "Serão feitas ${questions_count} etapa(s) de comando(s)." \
                    "Antes da execução você verá um relatório com os comandos exatos para confirmar." \
                    "" \
                    "Deseja continuar?")
                _zshmap_it_whiptail_plain --title "🧪 Testes interativos" \
                    --yes-button "Continuar" --no-button "Cancelar" \
                    --yesno "$preamble_body" \
                    17 72
                local preamble_rc=$?
                if [ "$preamble_rc" -ne 0 ]; then
                    echo "❌ Operação cancelada pelo usuário."
                    return 1
                fi
            fi
            
            local qi=0
            while (( qi < questions_count )); do
                local question_id
                question_id=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].id" "$yaml_file")
                local question_type
                question_type=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].type" "$yaml_file")
                local question_title
                question_title=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].title" "$yaml_file")
                local question_message
                question_message=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].message" "$yaml_file")
                local question_default
                question_default=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].default" "$yaml_file")
                [ "$question_default" = "null" ] && question_default=""
                
                case "$question_type" in
                "yesno")
                    # Sim/Não na lista + Avançar; um único «Voltar» no botão Cancelar (igual às outras etapas).
                    # --notags: não exibir coluna «1»/«2» (só rótulos). default do YAML: true/yes/1 → Sim (1); false/no/0 → Não (2).
                    local yn_body yn_hint yn_msg
                    yn_body=$(_zshmap_it_step_body "$((qi + 1))" "$questions_count" "$question_title" "" "$question_message")
                    yn_hint="Selecione Sim ou Não na lista e pressione Avançar. Voltar retorna à etapa anterior."
                    yn_msg=$(printf '%s\n\n%s' "$yn_body" "$yn_hint")
                    local yn_def_raw
                    yn_def_raw=$(echo "$question_default" | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')
                    local yn_default_item="1"
                    case "$yn_def_raw" in
                        false|no|0|off) yn_default_item="2" ;;
                        true|yes|1|on) yn_default_item="1" ;;
                        *) yn_default_item="1" ;;
                    esac
                    local yn_items=("1" "Sim" "2" "Não")
                    local yn_sel=""
                    yn_sel=$(_zshmap_it_whiptail_fancy --title "$question_title" \
                        --ok-button "Avançar" --cancel-button "Voltar" \
                        --notags \
                        --default-item "$yn_default_item" \
                        --menu "$yn_msg" 22 72 4 "${yn_items[@]}")
                    local yn_menu_rc=$?
                    local answer
                    if [ "$yn_menu_rc" -ne 0 ]; then
                        if (( qi > 0 )); then
                            ((qi--))
                            continue
                        fi
                        echo "❌ Operação cancelada pelo usuário."
                        return 1
                    fi
                    case "$yn_sel" in
                        1) answer=0 ;;  # Sim (mesma convenção antiga: 0 = sim)
                        2) answer=1 ;;  # Não
                        *)
                            if (( qi > 0 )); then
                                ((qi--))
                                continue
                            fi
                            echo "❌ Operação cancelada pelo usuário."
                            return 1
                            ;;
                    esac
                    case "$question_id" in
                        "recreate_env") recreate_env_answer=$answer ;;
                        "no_coverage") no_coverage_answer=$answer ;;
                    esac
                    ;;
                "menu")
                    local options_array=()
                    local option_count
                    option_count=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].options | length" "$yaml_file")
                    
                    local option_text
                    option_text=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].option_text" "$yaml_file" 2>/dev/null)
                    
                    local menu_extra=""
                    if [ "$option_text" != "null" ] && [ -n "$option_text" ]; then
                        menu_extra="$option_text"
                    fi
                    local final_message
                    final_message=$(_zshmap_it_step_body "$((qi + 1))" "$questions_count" "$question_title" "$menu_extra" "$question_message")
                    
                    local j
                    for ((j=0; j<option_count; j++)); do
                        local option_label
                        option_label=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].options[$j].label" "$yaml_file" 2>/dev/null)
                        
                        if [ "$option_label" != "null" ] && [ -n "$option_label" ]; then
                            options_array+=("$((j+1))" "$option_label")
                        else
                            local option
                            option=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].options[$j]" "$yaml_file")
                            options_array+=("$((j+1))" "$option")
                        fi
                    done
                    
                    local selected=""
                    selected=$(_zshmap_it_whiptail_fancy --title "$question_title" \
                        --ok-button "Avançar" --cancel-button "Voltar" \
                        --menu "$final_message" 24 72 10 "${options_array[@]}")
                    local menu_rc=$?
                    if [ "$menu_rc" -ne 0 ]; then
                        if (( qi > 0 )); then
                            ((qi--))
                            continue
                        fi
                        echo "❌ Operação cancelada pelo usuário."
                        return 1
                    fi
                    if ! [[ "$selected" =~ ^[1-9][0-9]*$ ]] || [ "$selected" -lt 1 ] || [ "$selected" -gt "$option_count" ]; then
                        if (( qi > 0 )); then
                            ((qi--))
                            continue
                        fi
                        echo "❌ Operação cancelada pelo usuário."
                        return 1
                    fi
                    
                    local opt_cmd_pick
                    opt_cmd_pick=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].options[$((selected-1))].command" "$yaml_file" 2>/dev/null)
                    if [ "$opt_cmd_pick" != "null" ] && [ -n "$opt_cmd_pick" ]; then
                        test_command_answer="$opt_cmd_pick"
                    else
                        test_command_answer=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .test_config.questions[$qi].options[$((selected-1))]" "$yaml_file")
                    fi
                    ;;
                "input")
                    local input=""
                    local ib_body
                    ib_body=$(_zshmap_it_step_body "$((qi + 1))" "$questions_count" "$question_title" "" "$question_message")
                    input=$(_zshmap_it_whiptail_fancy --title "$question_title" \
                        --ok-button "Avançar" --cancel-button "Voltar" \
                        --inputbox "$ib_body" \
                        20 72 "$question_default")
                    local ib_rc=$?
                    if [ "$ib_rc" -ne 0 ]; then
                        if (( qi > 0 )); then
                            ((qi--))
                            continue
                        fi
                        echo "❌ Operação cancelada pelo usuário."
                        return 1
                    fi
                    
                    case "$question_id" in
                        "testsuite") testsuite_answer="$input" ;;
                        "filter") filter_answer="$input" ;;
                    esac
                    ;;
                *)
                    _zshmap_it_whiptail_plain --title "❌ Erro" \
                        --msgbox "Tipo de pergunta não suportado no wizard de testes: $question_type" \
                        10 60
                    return 1
                    ;;
                esac
                
                ((qi++))
            done
            
            # Marcar que não é mais a primeira execução
            first_run=false
        fi
        
        # Montar comando de testes (sempre antes de recreate / docker exec): command_line no atalho ou em project.test_config
        local final_cmd wb_it_cmd_rc=0
        final_cmd=$(_zshmap_it_build_interactive_final_cmd "$yaml_file" "$shortcut_name" "$test_command_answer" "$testsuite_answer" "$filter_answer" "$no_coverage_answer") || wb_it_cmd_rc=$?
        if [ "$wb_it_cmd_rc" -ne 0 ] || [ -z "$final_cmd" ]; then
            _zshmap_it_whiptail_plain --title "❌ Configuração incompleta" \
                --msgbox "Montagem do comando de testes não definida no zshmap.yml.

Defina project.test_config.command_line (padrão do projeto) ou test_config.command_line no atalho interactive-test (sobrescreve o do projeto).

Campos: include_testsuite, testsuite_flag, include_filter_if_non_empty, filter_flag, include_no_coverage_when_sim, no_coverage_flag, no_coverage_answer_value, color_append_rules (lista de contains/append)." \
                18 75
            return 1
        fi
        
        if [ -z "$app_container" ] || [ "$app_container" = "null" ]; then
            echo "❌ Defina project.docker.containers.app no zshmap.yml (nome do container da aplicação)."
            return 1
        fi
        
        local docker_cmd="docker exec -it -e TERM=xterm-256color -e FORCE_COLOR=1 -e COLUMNS=$(tput cols) -e LINES=$(tput lines) $app_container $final_cmd"
        
        export TERM=xterm-256color
        export FORCE_COLOR=1
        export COLUMNS=$(tput cols 2>/dev/null || echo 120)
        export LINES=$(tput lines 2>/dev/null || echo 30)
        
        # Relatório de execução (uma vez por sessão do wizard, antes do primeiro run real)
        if [ "$wb_it_preview_done" = false ]; then
            if [ "$recreate_env_answer" = "0" ]; then
                if [ -z "$setup_shortcut" ] || [ "$setup_shortcut" = "null" ]; then
                    _zshmap_it_whiptail_plain --title "❌ Configuração incompleta" \
                        --msgbox "Você pediu para recriar o ambiente, mas project.test_config.setup_shortcut não está definido no zshmap.yml." \
                        12 70
                    return 1
                fi
            fi
            local recreate_line="Não (testes usarão o ambiente atual)"
            if [ "$recreate_env_answer" = "0" ]; then
                recreate_line="Sim — atalho ZshMap: ${setup_shortcut}"
            fi
            local rep_cov="padrão do PHPUnit/Laravel (sem --no-coverage)"
            if [ "$no_coverage_answer" = "0" ]; then
                rep_cov="coverage desabilitado (--no-coverage)"
            fi
            local rep_filter_show="${filter_answer}"
            [ -z "$rep_filter_show" ] && rep_filter_show="(nenhum)"
            
            local recreate_exact_section=""
            if [ "$recreate_env_answer" = "0" ]; then
                recreate_exact_section=$({
                    printf '%s\n' \
                        "   Chamada ZshMap (equivalente ao que será executado):" \
                        "     execute_shortcut \"${project_name}\" \"${setup_shortcut}\"" \
                        ""
                    local proj_root_rep
                    proj_root_rep=$(yq -r ".project.root" "$yaml_file" 2>/dev/null)
                    proj_root_rep="${proj_root_rep/#\~/$HOME}"
                    local step_n=1
                    local ch_sc=""
                    while IFS= read -r ch_sc; do
                        [ -z "$ch_sc" ] && continue
                        printf '%s\n' "   ─── Etapa ${step_n} (recreate) — atalho «${ch_sc}» ───"
                        local sc_path_rep
                        sc_path_rep=$(yq -r ".project.shortcuts[] | select(.name == \"$ch_sc\") | .path" "$yaml_file" 2>/dev/null)
                        [ "$sc_path_rep" = "null" ] && sc_path_rep="."
                        printf '%s\n' "      Pasta do projeto: ${proj_root_rep}/${sc_path_rep}"
                        printf '%s\n' "      Comandos no YAML (podem usar \$(cmd) que expande na hora de rodar):"
                        _zshmap_it_commands_lines_for_shortcut "$yaml_file" "$ch_sc"
                        printf '\n'
                        step_n=$((step_n + 1))
                    done < <(_zshmap_it_ordered_setup_chain "$yaml_file" "$setup_shortcut")
                })
            fi
            
            local exec_report=""
            exec_report=$(printf '%s\n' \
                "═══════════════════════════════════════════════════════════════" \
                " RELATÓRIO DE EXECUÇÃO — Testes interativos" \
                "═══════════════════════════════════════════════════════════════" \
                "" \
                "Use ↑↓ PageUp/PageDown para rolar. Depois confirme na próxima tela." \
                "" \
                "▶ COMANDOS EXATOS (nesta ordem)" \
                "")
            
            if [ "$recreate_env_answer" = "0" ]; then
                exec_report+=$(printf '%s\n' \
                    "" \
                    "1) RECRIAR AMBIENTE (antes dos testes)" \
                    "${recreate_exact_section}")
            else
                exec_report+=$(printf '%s\n' \
                    "" \
                    "1) RECRIAR AMBIENTE — não (pula esta etapa)")
            fi
            
            exec_report+=$(printf '%s\n' \
                "" \
                "2) TESTES — comando dentro do container:" \
                "     ${final_cmd}" \
                "" \
                "3) TESTES — linha completa no host (como será executada):" \
                "     ${docker_cmd}" \
                "" \
                "───────────────────────────────────────────────────────────────" \
                " Resumo das escolhas" \
                "" \
                "Projeto (pasta): ${project_name}" \
                "Atalho YAML:    ${shortcut_name}" \
                "" \
                "• Recriar ambiente: ${recreate_line}" \
                "• Ferramenta base:  ${test_command_answer}" \
                "• Test suite:        ${testsuite_answer}" \
                "• Filtro:            ${rep_filter_show}" \
                "• Coverage:          ${rep_cov}" \
                "• Container (app):   ${app_container}" \
                "" \
                "═══════════════════════════════════════════════════════════════")
            
            local report_file
            report_file=$(mktemp "/tmp/zshmap-exec-report.XXXXXX") || {
                echo "❌ Não foi possível criar arquivo temporário do relatório."
                return 1
            }
            printf "%s\n" "$exec_report" > "$report_file"

            _zshmap_it_whiptail_plain --title "📋 Relatório de execução" \
                --scrolltext \
                --textbox "$report_file" \
                30 84
            local scroll_rc=$?
            rm -f "$report_file"
            if [ "$scroll_rc" -ne 0 ]; then
                echo "❌ Execução abortada pelo usuário (relatório)."
                return 1
            fi
            
            _zshmap_it_whiptail_plain --title "✅ Confirmar" \
                --yesno "Confirmar execução conforme o relatório?\n\n<Sim> Iniciar execução comando(s)\n<Não> Cancelar" \
                12 70
            local confirm_rc=$?
            if [ "$confirm_rc" -ne 0 ]; then
                echo "❌ Execução cancelada pelo usuário."
                return 1
            fi
            
            wb_it_preview_done=true
        fi
        
        # Executar recriação do ambiente se necessário (apenas uma vez)
        if [ "$recreate_env_answer" = "0" ] && [ "$environment_recreated" = false ]; then
            if [ -z "$setup_shortcut" ] || [ "$setup_shortcut" = "null" ]; then
                echo "❌ Defina project.test_config.setup_shortcut no zshmap.yml (atalho que recria DB/migrations antes dos testes)."
                return 1
            fi
            echo "🔄 Executando $setup_shortcut..."
            execute_shortcut "$project_name" "$setup_shortcut"
            if [ $? -ne 0 ]; then
                echo "❌ Falha ao recriar ambiente"
                return 1
            fi
            environment_recreated=true
        fi
        
        # Executar comando
        echo "🧪 Executando: $final_cmd"
        echo "════════════════════════════════════════════════════════════════"
        
        eval "$docker_cmd"
        
        local exit_code=$?
        
        echo "════════════════════════════════════════════════════════════════"
        if [ $exit_code -eq 0 ]; then
            echo "✅ Comando(s) executado(s) com sucesso!"
        else
            echo "❌ Comando(s) falh(ou)ado(s)!"
        fi
        echo "════════════════════════════════════════════════════════════════"
        
        # Verificar se deve mostrar output e pausar
        local show_output=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .show_output" "$yaml_file")
        if [ "$show_output" = "true" ]; then
            echo ""
            echo "Pressione Enter para continuar..."
            read -r
        fi
        
        # Perguntar se deseja executar novamente
        echo ""
        _zshmap_it_whiptail_plain --title "🔄 Repetir Execução" --yesno "Deseja executar o comando novamente?" 10 60
        local rep_rc=$?
        if [ "$rep_rc" -ne 0 ]; then
            echo "👋 Saindo do modo de repetição..."
            break
        fi
        
        echo "🔄 Executando novamente com as mesmas configurações..."
        echo ""
    done
    
    return 0
}

# Função legada: delega ao assistente «interactive-test» definido no zshmap.yml do projeto.
# Configure project.test_config.interactive_test_shortcut com o name de um shortcut type: interactive-test.
execute_test() {
    local project_name="$1"
    local yaml_file
    yaml_file=$(get_project_yaml_path "$project_name")
    if [ $? -ne 0 ] || [ -z "$yaml_file" ]; then
        echo "❌ Arquivo zshmap.yml (ou workerboss.yml legado) não encontrado para o projeto $project_name!"
        return 1
    fi
    if ! validate_yaml_file "$yaml_file"; then
        echo "❌ YAML inválido: $yaml_file"
        return 1
    fi
    local shortcut_name
    shortcut_name=$(yq -r '.project.test_config.interactive_test_shortcut // ""' "$yaml_file" 2>/dev/null)
    if [ -z "$shortcut_name" ] || [ "$shortcut_name" = "null" ]; then
        echo "❌ Defina project.test_config.interactive_test_shortcut no zshmap.yml do projeto \"$project_name\"."
        echo "   Use o campo name de um shortcut com type: interactive-test (perguntas em test_config.questions desse atalho)."
        return 1
    fi
    local sc_type
    sc_type=$(yq -r ".project.shortcuts[] | select(.name == \"$shortcut_name\") | .type" "$yaml_file" 2>/dev/null)
    if [ "$sc_type" != "interactive-test" ]; then
        echo "❌ O atalho \"$shortcut_name\" deve ser type \"interactive-test\" (encontrado: ${sc_type:-vazio})."
        return 1
    fi
    echo "ℹ️ execute_test → assistente \"$shortcut_name\" (project.name no YAML: $(yq -r '.project.name // "—"' "$yaml_file" 2>/dev/null))"
    execute_interactive_test "$project_name" "$shortcut_name" "$yaml_file"
    return $?
}

# Função para limpar cache ao sair
cleanup_on_exit() {
    clear_sudo_password_cache
    echo -e "\n\n${GREEN}✅ Cache de senha limpo com segurança${NC}"
}

# Tratamento de interrupção (Ctrl+C)
trap 'cleanup_on_exit; exit 0' INT

# Executar programa principal
main "$@"

