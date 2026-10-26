# adb-wifi-qr

Ventana para Windows que conecta un celular Android por **Depuración inalámbrica** (ADB por Wi-Fi), incluida la vinculación **escaneando un código QR**.

- **Vincular con QR**: escaneás el QR que muestra la PC y la app vincula y conecta sola.
- **Solo conectar**: si ya estaba vinculado, reconecta. Con el puerto vacío (o viejo) se lo pregunta al celular por mDNS.
- **Vincular + conectar**: vinculación manual con IP, puerto de vinculación y código de 6 dígitos.
- Recuerda la última IP/puerto que conectó.

Sin dependencias: PowerShell 5.1 + `adb`. El QR y el cliente mDNS están incluidos (no usa `adb mdns`, que suele fallar en redes "Públicas" de Windows).

## Requisitos

- Windows 10/11 (PowerShell 5.1, ya viene instalado).
- Android 11 o superior, con **Opciones de desarrollador** activadas.
- PC y celular en la **misma red Wi-Fi**.
- `adb` (platform-tools).

## Instalación

1. Instalá adb (una de las dos):
   ```powershell
   winget install Google.PlatformTools
   ```
   o descargá [platform-tools](https://developer.android.com/tools/releases/platform-tools) y agregalo al `PATH`.
2. Descargá este repo (`Code` → `Download ZIP`, o `git clone`) y dejá los 4 archivos juntos en una carpeta:
   `ADB-Vincular.bat`, `ADB-Vincular.ps1`, `ADB-QR-Encoder.ps1`, `ADB-Mdns.ps1`.
3. Doble clic en `ADB-Vincular.bat` (opcional: creá un acceso directo en el Escritorio).

La app busca `adb.exe` en este orden: variable `ADB_PATH`, `PATH`, winget y Android SDK.

## Uso

**Primera vez (QR)**
1. En el celular: *Ajustes → Opciones de desarrollador → Depuración inalámbrica* (activada) → **Vincular dispositivo mediante código QR**.
2. En la app: **VINCULAR CON CODIGO QR** y apuntá la cámara al código.
3. Se vincula y conecta solo.

**Después**
- Poné la IP del celular y tocá **SOLO CONECTAR**. El puerto puede ir vacío.

**Vinculación manual**: *Vincular con código de sincronización* en el celular → completá IP, puerto de vinculación y código → **VINCULAR + CONECTAR**.

## Problemas comunes

- *"El celular no responde"*: pantalla encendida, Depuración inalámbrica activa y misma red. Algunas redes (invitados, repetidores) aíslan los dispositivos entre sí.
- *Sigue sin detectar el QR*: el código vence en pocos segundos al cerrar la pantalla del escáner; abrilo de nuevo en el celular.
- *Reiniciar servidor ADB* soluciona estados raros de `adb`.

## Licencia

MIT
