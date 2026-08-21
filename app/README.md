# GranMap App

Aplicativo Flutter local-first de orientação, agenda acadêmica e comunidade.

No navegador o posicionamento usa o simulador determinístico. Em Android/iOS,
o usuário pode ativar sensores físicos, câmera, GPS e QR. O GranMap Lab também
coleta fingerprints magnéticos para uma versão publicada do mapa.

```powershell
flutter pub get
flutter run -d chrome --dart-define=GRANMAP_API_URL=http://127.0.0.1:8000
```

No emulador Android, use `http://10.0.2.2:8000`. Em um aparelho físico, inicie
o backend com `uvicorn main:app --host 0.0.0.0 --reload` e use o IP local do
computador; ambos precisam estar na mesma rede.

O Android aceita HTTP apenas no manifest de debug; o manifest principal e o
iOS exigem HTTPS, mantendo somente a descoberta da rede local.

O flavor principal já bloqueia HTTP e o build release não reutiliza a chave de
debug. Antes de publicar no Android, copie `android/key.properties.example`
para `android/key.properties`, aponte para o keystore institucional e guarde
ambos fora do Git.

Validação:

```powershell
flutter analyze
flutter test
```
