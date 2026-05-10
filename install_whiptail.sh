#!/bin/bash

# Script de instalação do ZshMap com Whiptail
# Menu e geração de ambiente Zsh a partir de YAML

echo "🚀 Instalando dependências para o ZshMap..."

# Atualizar lista de pacotes
echo "📦 Atualizando lista de pacotes..."
sudo apt update

# Instalar whiptail (interface gráfica no terminal)
echo "🎨 Instalando Whiptail..."
sudo apt install -y whiptail

# Instalar outras dependências úteis
echo "🔧 Instalando dependências adicionais..."
sudo apt install -y dialog curl wget git

# Verificar se a instalação foi bem-sucedida
if command -v whiptail &> /dev/null; then
    echo "✅ Whiptail instalado com sucesso!"
else
    echo "❌ Erro na instalação do Whiptail"
    exit 1
fi

echo ""
echo "🎉 Instalação concluída com sucesso!"
echo ""
echo "🚀 Para executar o ZshMap:"
echo "   ./zsh-map.sh"
echo ""
echo "📖 Recursos disponíveis:"
echo "   • Interface gráfica moderna no terminal"
echo "   • Menus interativos e responsivos"
echo "   • Barras de progresso visuais"
echo "   • Confirmações de segurança"
echo "   • Tratamento de erros robusto"
echo ""
echo "🌟 ZshMap está pronto para uso!"
