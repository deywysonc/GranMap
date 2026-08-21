# GranMap Admin

Com o backend já rodando:

```powershell
cd C:\GranMap\admin_web
npm install
npm run dev
```

Abra o endereço mostrado pelo Vite (normalmente `http://localhost:5173`).

O painel exige uma conta com papel `moderator`, `coordination` ou
`admin`. Promova uma conta já cadastrada com:

```powershell
cd C:\GranMap\backend
python promote_user.py seu@email.com admin
```

Para apontar a outra API, crie `.env.local`:

```text
VITE_GRANMAP_API_URL=http://IP-DO-SERVIDOR:8000
```

Moderadores atuam apenas na comunidade/auditoria. Coordenação e administradores
também mantêm cursos, professores, ambientes e ensalamento oficial.

Coordenação/admin também operam versões do mapa, preview por piso, publicação,
bloqueios de corredores e âncoras QR. O login web usa cookie HttpOnly e CSRF;
tokens não ficam em `localStorage`.

```powershell
npm test
npm run build
```
