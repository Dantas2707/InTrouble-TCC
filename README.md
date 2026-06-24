# InTrouble - Aplicativo de Apoio e Proteção 🛡️

> Trabalho de Conclusão de Curso (TCC) - Centro Universitário do Distrito Federal (UDF)

**InTrouble** é um aplicativo mobile desenvolvido com o objetivo de oferecer apoio e proteção para vítimas em situação de vulnerabilidade. O aplicativo fornece ferramentas de alerta rápido, permitindo que usuários contatem "guardiões" (contatos de confiança) e reportem ocorrências de forma eficiente.

---

## 📱 Funcionalidades Principais

* **Alertas de Emergência:** Envio ágil de mensagens (SMS/E-mail) para contatos pré-cadastrados em situações de perigo.
* **Rede de Apoio (Guardiões):** Cadastro e gerenciamento de contatos de confiança para monitoramento e socorro.
* **Registro de Ocorrências:** Ferramenta para documentar incidentes, incluindo a definição do tipo de ocorrência e seu nível de gravidade.
* **Autenticação e Perfil:** Sistema de login e gerenciamento de informações pessoais para garantir a segurança e privacidade do usuário.

## 🛠️ Tecnologias e Ferramentas

O aplicativo foi construído utilizando as seguintes tecnologias:

* **[Flutter](https://flutter.dev/):** Framework principal utilizado para o desenvolvimento da interface multiplataforma (Android/iOS).
* **[Dart](https://dart.dev/):** Linguagem de programação base do Flutter.
* **[Firebase](https://firebase.google.com/):** Serviços de backend da Google.
  * **Cloud Firestore:** Banco de dados NoSQL utilizado para persistência dos dados (usuários, guardiões, ocorrências).
  * (Inclui integrações para envio de e-mails e mensagens conforme arquitetura do projeto).

## 📁 Estrutura do Projeto

A estrutura de diretórios do `lib/` reflete a organização das telas e serviços:

* `/Pages`: Contém todas as interfaces de usuário (Telas de Login, Home, Guardiões, Ocorrências, Configurações, etc.).
* `/services`: Módulos responsáveis pela lógica de negócio e integração com APIs externas (Firestore, serviços de envio de mensagens e e-mails).

## 📚 Documentação (TCC)

A documentação completa contendo o referencial teórico, requisitos, diagramas e conclusões da pesquisa encontra-se no arquivo **[TCC.pdf](./TCC.pdf)** presente neste repositório, intitulado *"APLICATIVO DE APOIO E PROTEÇÃO PARA VÍTIMAS EM SITUAÇÃO DE VULNERABILIDADE"*.
