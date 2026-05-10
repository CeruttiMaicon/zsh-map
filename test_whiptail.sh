#!/bin/bash

# Teste simples da interface Whiptail

echo "🧪 Testando interface Whiptail..."

# Teste básico de mensagem
whiptail --title "🧪 Teste" \
          --msgbox "Interface Whiptail funcionando perfeitamente!\n\nClique OK para continuar." \
          8 50

# Teste de menu
choice=$(whiptail --title "🎯 Menu de Teste" \
                  --menu "Escolha uma opção:" \
                  10 40 4 \
                  "1" "✅ Opção 1" \
                  "2" "✅ Opção 2" \
                  "3" "✅ Opção 3" \
                  3>&1 1>&2 2>&3)

if [ $? -eq 0 ]; then
    echo "Você escolheu: $choice"
else
    echo "Operação cancelada"
fi

echo "✅ Teste concluído com sucesso!"
