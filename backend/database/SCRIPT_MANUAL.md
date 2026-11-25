# Ejecutar el SQL desde pgAdmin

Este procedimiento es una alternativa al asistente automático. Úsalo únicamente con una base nueva y vacía. Si el backend ya creó las tablas con Flyway, no vuelvas a ejecutar el script.

1. En pgAdmin, crea `clinica_informatica` (Databases → Create → Database). Preferentemente usa `clinica_app` como propietario, si ya existe.
2. Selecciona esa base y abre Query Tool.
3. Abre `database/clinica_informatica_completa.sql` y ejecuta todo el archivo (F5). Crea las 18 tablas, relaciones, restricciones, índices, triggers, vista y catálogos en una transacción.
4. Si aparece un error, ejecuta `ROLLBACK;` antes de volver a intentarlo. No ejecutes fragmentos por separado.

Si prefieres crear la base mediante SQL, ejecuta esta sentencia sola, conectado a `postgres` y fuera de una transacción; después abre Query Tool en la base nueva:

```sql
CREATE DATABASE clinica_informatica WITH ENCODING 'UTF8';
```

## Conectar el backend después del SQL manual

El script equivale a las migraciones V1 y V2, pero no crea el historial de Flyway. Solo después de ejecutar correctamente este archivo completo en la base vacía, inicia el backend una vez con estas variables en PowerShell, desde la raíz del proyecto:

```powershell
$env:SPRING_FLYWAY_BASELINE_ON_MIGRATE = 'true'
$env:SPRING_FLYWAY_BASELINE_VERSION = '2'
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-Backend.ps1
```

El backend usa `postgres` por defecto para conectarse a la base y ejecutar las migraciones. Introduce su contraseña localmente cuando el asistente la solicite. Para un entorno compartido o de producción, es preferible configurar un usuario de aplicación con permisos limitados.

Flyway registra la versión 2 como punto de partida y no intenta crear de nuevo las tablas. Las migraciones posteriores, desde V3, se ejecutarán normalmente. No uses estas variables con una base distinta o incompleta: el baseline registra una versión, pero no comprueba que las tablas coincidan.

Después de detener el backend, elimina esas variables de esa terminal:

```powershell
Remove-Item Env:\SPRING_FLYWAY_BASELINE_ON_MIGRATE
Remove-Item Env:\SPRING_FLYWAY_BASELINE_VERSION
```

El administrador de la aplicación se crea al iniciar el backend con `ADMIN_PASSWORD` (el asistente la pide). El SQL no introduce usuarios con contraseñas predeterminadas.

## Agregar cotizaciones a una base existente

Si la base ya contiene clientes, equipos y órdenes, ejecuta
`database/SCRIPT_COTIZACIONES.sql` en pgAdmin seleccionando primero
`clinica_informatica`.

Este script es idempotente: crea o completa las tablas de cotización y detalles,
conecta cada cotización con una orden, cliente, equipo y usuario, agrega los
permisos del módulo y recalcula automáticamente subtotales y totales. La vista
`quotation_detail_view` permite consultar las cotizaciones con sus datos
relacionados.
