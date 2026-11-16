# Water Tracker KC

Recordatorio de agua para iPhone y iPad. Registras lo que bebes, la app lo guarda en Apple Health y te avisa con notificaciones locales cuando toca beber.

## Privacidad

Tus datos solo van a Apple Health y a tu propio iCloud.

- El agua se guarda en Apple Health. La app no tiene base de datos propia. Si tienes Salud activada en iCloud, Apple sincroniza ese historial entre tus dispositivos.
- Los ajustes se guardan en el dispositivo y se sincronizan con el almacenamiento clave-valor de tu iCloud, que es privado de tu cuenta.
- No hay cuenta, analíticas, publicidad, paquetes de terceros, servidores propios ni código de red.
- No usa CloudKit ni notificaciones push remotas. Los recordatorios se programan en el propio dispositivo.

`scripts/check-privacy.sh` comprueba estas reglas y se ejecuta en cada pull request.

## Funciones

- Registro rápido con tres cantidades configurables, o cualquier otra cantidad.
- Deshacer y borrar registros del día.
- Historial de 7 y 30 días con promedio, días con la meta cumplida y racha.
- Recordatorios locales cada cierto tiempo desde tu último registro, con horario de silencio y un botón para registrar desde la notificación. Se detienen por el día al cumplir la meta.
- Widget para la pantalla de inicio y la pantalla de bloqueo.
- Siri y Atajos: "Registrar agua en Water Tracker KC" o "Log water in Water Tracker KC".
- Mililitros u onzas líquidas. Interfaz en español e inglés.

## Requisitos

- Xcode 26 o posterior.
- iOS o iPadOS 26 o posterior.

## Cómo compilar

1. Abre `WaterTracker.xcodeproj`.
2. En los targets `WaterTracker` y `WaterTrackerWidget`, elige tu equipo en Signing & Capabilities.
3. Si cambias el identificador `com.kevincsv.hidrata`, cambia también el grupo `group.com.kevincsv.hidrata` en los dos archivos `.entitlements` y en `Shared/DaySnapshot.swift`.
4. Ejecuta en un iPhone o iPad. Apple Health no está disponible en todos los simuladores.

Las pruebas unitarias se ejecutan con Cmd+U o con:

```sh
xcodebuild test -project WaterTracker.xcodeproj -scheme WaterTracker -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Publicar en TestFlight

El flujo `TestFlight` de GitHub Actions compila, firma y sube la app sin necesidad de un Mac. Se lanza a mano desde la pestaña Actions o al subir una etiqueta como `v2.0`. Necesita estos secretos en el repositorio:

| Secreto | Valor |
| --- | --- |
| `ASC_KEY_ID` | ID de la clave de API de App Store Connect |
| `ASC_ISSUER_ID` | Issuer ID de App Store Connect |
| `ASC_KEY_P8` | El archivo `.p8` de la clave, en base64 |
| `APPLE_TEAM_ID` | ID del equipo de Apple Developer |

La clave debe tener rol Admin para que la firma automática en la nube pueda crear certificados y perfiles. Antes de la primera subida, la app debe existir en App Store Connect con el identificador `com.kevincsv.hidrata`.

## Estructura

| Carpeta | Contenido |
| --- | --- |
| `WaterTracker/` | La app: vistas, Apple Health, recordatorios, Siri |
| `WaterTracker Widget/` | El widget |
| `Shared/` | Código y textos que comparten la app y el widget |
| `WaterTrackerTests/` | Pruebas unitarias |

## Créditos y licencia

Basada en [WaterTracker](https://github.com/SteveLeungYL/WaterTracker) de Yu Liang, publicada bajo la licencia MIT. La animación de ola viene de [RedDragonJ/Swift-Learning](https://github.com/RedDragonJ/Swift-Learning). Consulta `LICENSE`.
