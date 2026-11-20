# Water Tracker KC

Recordatorio de agua para iPhone y iPad. Registras lo que bebes, la app lo guarda en Apple Health y te avisa con notificaciones locales cuando toca beber.

## Privacidad

Tus datos solo van a Apple Health y a tu propio iCloud.

- El agua se guarda en Apple Health. La app no tiene base de datos propia. Si tienes Salud activada en iCloud, Apple sincroniza ese historial entre tus dispositivos.
- El widget lee el progreso del día de un elemento del llavero compartido entre la app y el widget, marcado como solo de este dispositivo.
- Los ajustes se guardan en el dispositivo y se sincronizan con el almacenamiento clave-valor de tu iCloud, que es privado de tu cuenta.
- Las comidas que apuntas también se guardan en Apple Health (calorías y macros), de donde WHOOP las recoge para su Journal.
- Mis comidas, recetas, rutinas y entrenos se guardan solo en el dispositivo (SwiftData con CloudKit desactivado).
- La única conexión a internet es la búsqueda de códigos de barras en `world.openfoodfacts.org`, que recibe solo el número del código (`WaterTracker/Food/Scan/OpenFoodFacts.swift`). Las fotos de etiquetas y comidas se procesan en el dispositivo y no se guardan ni se envían.
- No hay cuenta, analíticas, publicidad, paquetes de terceros ni servidores propios.
- Amigos (opcional, apagado por defecto): si activas «Empezar a compartir», tu nombre, tu meta y tu total de agua de cada día de las últimas cuatro semanas se guardan en una zona privada de tu iCloud (CloudKit) y se comparten en solo lectura con las personas que invites, mediante el sistema de compartir de Apple. No hay servidor propio ni datos públicos. «Dejar de compartir» borra esa zona de iCloud. CloudKit solo se usa en `WaterTracker/Friends`.
- No usa notificaciones push remotas. Los recordatorios se programan en el propio dispositivo.

`scripts/check-privacy.sh` comprueba estas reglas y se ejecuta en cada pull request.

## Funciones

- Registro rápido con tres cantidades configurables, o cualquier otra cantidad.
- Deshacer y borrar registros del día.
- Historial de 7 y 30 días con promedio, días con la meta cumplida y racha.
- Recordatorios locales cada cierto tiempo desde tu último registro, con horario de silencio y un botón para registrar desde la notificación. Se detienen por el día al cumplir la meta.
- Amigos: invita a amigos que usen la app y comparen el agua de esta semana o la pasada, con una clasificación según la meta de cada uno.
- Widget para la pantalla de inicio y la pantalla de bloqueo.
- Comidas: apunta calorías y macros por ración o por 100 g, con objetivo diario y las calorías activas del día. Rellena por código de barras (Open Food Facts), con una foto de la etiqueta nutricional UK/UE leída en el dispositivo, o describiendo o fotografiando la comida para una estimación de Apple Intelligence en el dispositivo. Mis comidas y recetas con ingredientes y raciones.
- Entrenos: rutinas, series con repeticiones y peso (kg o lb), y lo que hiciste la última vez en cada ejercicio.
- Siri y Atajos: "Registrar agua en Water Tracker KC" o "Log water in Water Tracker KC".
- Mililitros u onzas líquidas. Interfaz en español e inglés (Comidas y Entrenos, de momento solo en español).

## Requisitos

- Xcode 27 o posterior (SDK de iOS 27).
- iOS o iPadOS 26 o posterior.

## Cómo compilar

1. Abre `WaterTracker.xcodeproj`.
2. En los targets `WaterTracker` y `WaterTrackerWidget`, elige tu equipo en Signing & Capabilities.
3. Si cambias el identificador `com.kevincsv.hidrata`, cambia también el grupo de llavero `com.kevincsv.hidrata.shared` en los dos archivos `.entitlements`.
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
| `WaterTracker/Food/` | Comidas: Salud, escáner, estimación con IA y recetas |
| `WaterTracker/Workouts/` | Rutinas, entrenos e historial de ejercicios |
| `WaterTracker Widget/` | El widget |
| `Shared/` | Código y textos que comparten la app y el widget |
| `WaterTrackerTests/` | Pruebas unitarias |

## Créditos y licencia

Basada en [WaterTracker](https://github.com/SteveLeungYL/WaterTracker) de Yu Liang, publicada bajo la licencia MIT. La animación de ola viene de [RedDragonJ/Swift-Learning](https://github.com/RedDragonJ/Swift-Learning). Consulta `LICENSE`.
