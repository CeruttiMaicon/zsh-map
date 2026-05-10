#!/bin/bash

## Instala curl
sudo apt install curl -y;

### Instalações via ZSH
## Prompt ZSH
sudo apt install zsh -y;

sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)";

## Instalação auto-suggestion
sudo git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

## Instalação syntax-highlighting
sudo git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Daí adicione zsh-autosuggestions na lista de plugins do seu “~/.zshrc”:
# plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting)

# Atualiza a lista de plugins no ~/.zshrc
ZSHRC="$HOME/.zshrc"
if grep -q '^plugins=' "$ZSHRC"; then
    # Se a linha 'plugins=' já existir, atualize-a
    sed -i.bak '/^plugins=/c\plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting)' "$ZSHRC"
else
    # Se a linha 'plugins=' não existir, adicione-a
    echo 'plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSHRC"
fi

# Criando link simbolico
ln -s ${PWD}/.zprofile ${HOME}/.zprofile ;

# Adiciona a linha para incluir ~/.zprofile no ~/.zshrc, se ainda não estiver lá
if ! grep -q 'source ~/.zprofile' "$ZSHRC"; then
    echo 'source ~/.zprofile' >> "$ZSHRC"
fi
