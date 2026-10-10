# Mobile · Flutter

Requisitos: Flutter 3.47 o superior, un emulador Android o simulador iOS, y el backend corriendo (ver `../Backend/README.md`).

```bash
flutter pub get
flutter run
```

En el emulador de Android la app usa `http://10.0.2.2:3000`; en el simulador de iOS, `http://localhost:3000`.

En un teléfono físico, usar la IP de la computadora en la misma red Wi-Fi:

```bash
flutter run --dart-define=API_URL=http://192.168.1.50:3000
```

Con el backend desplegado en GCP, usar la URL de API Gateway:

```bash
flutter run --dart-define=API_URL=https://integrador-gateway-xxxx.uc.gateway.dev
```
