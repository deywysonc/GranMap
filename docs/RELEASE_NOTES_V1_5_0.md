# GranMap 1.5.0

Atualização de funcionamento e experiência de uso, build Android 11.

## Melhorias

- A rota abre sem aguardar a gravação do histórico, inclusive pela grade.
- Os controles de 3D, Walk e câmera têm uma área própria, acima do painel da rota.
- A prévia animada e o acompanhamento por sensores são ações distintas.
- A posição pode ser corrigida por QR ou confirmação manual na própria rota, incluindo o piso.
- Pausa, retomada, recálculo e ida para segundo plano preservam o estado correto dos sensores.
- Passos anteriores à navegação não são reaproveitados como deslocamento novo.
- Leituras GPS antigas ou concluídas depois de uma pausa não substituem a posição atual.
- Login e cadastro validam campos, mostram erros e não aguardam o contador de notificações.
- A grade e os dados pessoais têm limites de espera e tratamento de falhas de cache.
- Rotas iniciadas pelo perfil, pela grade e pelos favoritos respeitam os bloqueios recebidos.
- Favoritos usam uma fila local persistente; uma remoção offline não reaparece ao reconectar.
- Atualizações de contas diferentes não se misturam após login ou logout.
- Início, busca e perfil exibem favoritos do cache antes da resposta do servidor.
- Falhas ao remover a sessão oferecem uma nova tentativa no perfil de visitante.
- O endereço padrão do aplicativo aponta para a API HTTPS pública já existente.

## Instalação e ambiente

O flavor `demo` mantém o nome GranMap Demo e a assinatura de instalação usada
nas versões anteriores. O APK ARM64 é destinado aos celulares Android atuais;
os outros APKs têm o mesmo código, compilado para ARM de 32 bits e x86_64.

API usada: `https://granmap.168.119.244.43.sslip.io/api`.
Os arquivos desta versão ficam em `deliverables/GranMap-Demo-v1.5.0-*.apk`.

Para desenvolvimento local, o endereço continua configurável:

```powershell
flutter run -d web-server --web-port 8088 --dart-define=GRANMAP_API_URL=http://127.0.0.1:8100
```

Para iniciar os serviços sem recriar o banco existente:

```powershell
.\scripts\start_demo.ps1 -NoReset
```

`verify_demo.ps1` verifica o download de APK somente quando `-ApkUrl` é informado.

Neste Windows, o Java falhou ao criar seu socket interno no caminho temporário
abreviado do usuário. O build foi concluído com a opção abaixo somente no
processo de compilação, sem modificar configurações globais:

```powershell
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:/Windows/Temp'
flutter build apk --flavor demo --release --split-per-abi --no-pub `
  --dart-define=GRANMAP_API_URL=https://granmap.168.119.244.43.sslip.io/api
```

## Validação da entrega

Em 13/10/2026: 107 testes Flutter, 23 testes do backend e 3 do Admin aprovados.
A análise estática do app, os builds web/Android/Admin e a jornada HTTP local
também passaram. Os três APKs possuem assinatura v2; o certificado é o mesmo
da demo 1.4.1. O ARM64 contém o mapa v11 e os assets locais do Walk.

APK ARM64: 28.251.097 bytes. SHA-256:
`752348FEBF8097DB9ED42643051C89A8A4C6F6418B81D242D676E092E7C6FED5`.

Não havia celular conectado ou emulador configurado: a instalação no aparelho
e a validação presencial dos sensores não foram realizadas nesta tarefa.

## Limites de posicionamento

GPS reconhece a proximidade da faculdade; o piso interno vem de uma referência
confirmada. Sensores produzem uma estimativa aproximada que precisa de
reancoragem. A escala, o tamanho do passo e a direção ainda exigem calibração
presencial. Esta atualização não declara precisão indoor validada.

As alterações do backend neste pacote incluem exposição de ETag e identificador
de requisição para clientes web entre origens. Os arquivos de código e os novos
APKs são locais; esta tarefa não publica uma implantação no Coolify.
