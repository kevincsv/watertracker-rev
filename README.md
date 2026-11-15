# Hidrata

Recordatorio de agua para iPhone y iPad. Registras lo que bebes, la app lo guarda en Apple Health y te avisa con notificaciones locales cuando toca beber.

## Privacidad

Todo se queda en el dispositivo.

- El agua se guarda en Apple Health. La app no tiene base de datos propia.
- Los ajustes se guardan en el almacenamiento local de la app.
- No hay cuenta, analíticas, publicidad, paquetes de terceros ni código de red.
- No usa iCloud ni notificaciones push remotas. Los recordatorios se programan en el propio dispositivo.

`scripts/check-privacy.sh` comprueba estas reglas y se ejecuta en cada pull request. Si tienes activada la sincronización de Salud con iCloud en los Ajustes de iOS, Apple sincroniza tus datos de salud por su cuenta; eso lo controla el sistema y no esta app.

## Funciones

- Registro rápido con tres cantidades configurables, o cualquier otra cantidad.
- Deshacer y borrar registros del día.
- Historial de 7 y 30 días con promedio, días con la meta cumplida y racha.
- Recordatorios locales cada cierto tiempo desde tu último registro, con horario de silencio y un botón para registrar desde la notificación. Se detienen por el día al cumplir la meta.
- Widget para la pantalla de inicio y la pantalla de bloqueo.
- Siri y Atajos: "Registrar agua en Hidrata" o "Log water in Hidrata".
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

## Estructura

| Carpeta | Contenido |
| --- | --- |
| `WaterTracker/` | La app: vistas, Apple Health, recordatorios, Siri |
| `WaterTracker Widget/` | El widget |
| `Shared/` | Código y textos que comparten la app y el widget |
| `WaterTrackerTests/` | Pruebas unitarias |

## Créditos y licencia

Basada en [WaterTracker](https://github.com/SteveLeungYL/WaterTracker) de Yu Liang, publicada bajo la licencia MIT. La animación de ola viene de [RedDragonJ/Swift-Learning](https://github.com/RedDragonJ/Swift-Learning). Consulta `LICENSE`.
