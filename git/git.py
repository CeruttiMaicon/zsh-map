import subprocess

class Git:
    def __init__(self):
        self.programs = []

    def execute(self):
        subprocess.call('clear')
    
        print('Você irá configurar os parametros \n')
        print('user.name=???\n')
        print('user.email=???\n')
        # Mensagem para continuar ou não
        continuar = input('\nDeseja continuar? (S/N, Y/N)')
        if continuar == 'S' or continuar == 's' or continuar == 'y' or continuar == 'Y':
            userName = input('Digite para a configuração de nome: git config --global user.name:')
            userEmail = input('Digite para a configuração de nome: git config --global user.email:')
            subprocess.call('git config --global user.name ' + '"' + userName + '"' , shell=True)
            subprocess.call('git config --global user.email ' + '"' + userEmail + '"' , shell=True)
            print('\nConfiguração realizada com sucesso!')
            subprocess.call('git config --list', shell=True)
            input('\nPressione qualquer tecla para continuar...')
        else:
            print('\nConfiguração cancelada!')
            input('\nPressione qualquer tecla para continuar...')
            
