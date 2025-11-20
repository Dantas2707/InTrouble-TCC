# Aplicativo

Segue alguns comandos do Firebase e Git usados neste projeto.

Comandos Firebase e Flutter

>> Firebase CLI

npm install -g firebase-tools  
Instala as ferramentas da Firebase (CLI) de forma global no sistema.

firebase login  
Faz login na sua conta do Firebase pelo terminal.

>> FlutterFire CLI

flutter pub global activate flutterfire_cli  
Ativa a ferramenta do FlutterFire CLI para integrar Firebase com Flutter.

flutterfire configure  
Conecta seu app Flutter a um projeto Firebase e gera o arquivo de configuração (firebase_options.dart).

>> Pacotes do Firebase

flutter pub add firebase_core  
Adiciona o pacote principal do Firebase ao projeto Flutter.

flutter pub add cloud_firestore  
Adiciona o pacote do Firestore (banco de dados em tempo real) ao projeto.

>> Dependências e diagnóstico

flutter pub get  
Baixa e instala todos os pacotes listados no pubspec.yaml.

flutter doctor  
Verifica o ambiente de desenvolvimento Flutter e informa se há algo faltando.

>> Executar e gerar APK

flutter run  
Executa o app Flutter em um emulador ou dispositivo físico conectado.

flutter build apk --release  
Gera o APK final (otimizado para produção) do aplicativo para Android.


Comandos Git/GitHub


>> Inicializar repositório

git init  
Inicializa um repositório Git local.

>> Configuração (apenas na primeira vez)

git config --global user.name "Seu Nome"  
Define o nome do usuário para o Git.

git config --global user.email "seu@email.com"  
Define o e-mail do usuário para o Git.

>> Verificar status

git status  
Mostra os arquivos modificados e o que está pronto para commit.

>> Adicionar arquivos

git add .  
Adiciona todas as alterações ao stage (preparando para o commit).

>> Fazer commit

git commit -m "mensagem do commit"  
Salva as alterações com uma mensagem descritiva.

>> Conectar ao GitHub

git remote add origin https://github.com/seu-usuario/seu-repo.git  
Conecta seu repositório local ao repositório remoto no GitHub.

>> Enviar código para o GitHub

git push -u origin main  
Envia o código local para a branch principal (main) no GitHub.

>> Clonar repositório existente

git clone https://github.com/seu-usuario/seu-repo.git  
Copia um repositório remoto para sua máquina local.

>> Atualizar repositório local

git pull  
Baixa as últimas atualizações do repositório remoto.

>> Ver e mudar de branches

git branch  
Lista todas as branches locais.

git checkout -b nome-da-branch  
Cria e muda para uma nova branch.

git checkout main  
Volta para a branch principal.

>> Substituir arquivos com a versão do repositório remoto

git reset --hard origin/main  
Descarta todas as alterações locais e sincroniza com o remoto.


Links Úteis Flutter


Este projeto é um ponto de partida para aplicações Flutter.

Recursos para iniciantes:

Lab: Write your first Flutter app → https://docs.flutter.dev/get-started/codelab  
Cookbook: Useful Flutter samples → https://docs.flutter.dev/cookbook  

Documentação oficial → https://docs.flutter.dev  
(Tutoriais, exemplos, guia de desenvolvimento mobile e referência completa da API)
