# cleanup/README.md — cleanup-debian-testing.sh

> **Este archivo es:** el detalle técnico de `cleanup-debian-testing.sh`
> (el script que **elimina** apps). Léelo cuando quieras saber
> exactamente qué grupos de paquetes quita y por qué. Para el script
> que **instala/configura**, ve a `setup/README.md`. Para una guía paso
> a paso sin dar nada por sabido, ve a `MANUAL.md` en la raíz del
> proyecto.

Elimina aplicaciones de **KDE Plasma** que Debian instala por defecto
junto a la tarea de escritorio, pero que muchos usuarios no llegan a
usar (suite PIM/Kontact, herramientas de accesibilidad, Konqueror, xterm,
KDE Connect, Dragon Player, Juk, KDE Partition Manager, e ImageMagick de forma opcional). Es
el complemento de `setup-debian-testing.sh`: ese script instala, este
quita.

Esta lógica no depende de la rama de Debian ni del codename — los
nombres de paquete que revisa son los mismos en stable, testing o
unstable — por eso es un script sencillo, sin comprobaciones de suite
como las de `setup-debian-testing.sh`.

Versión documentada: **1.0.0**.

---

## Índice

- [Qué hace](#qué-hace)
- [Por qué es un script aparte](#por-qué-es-un-script-aparte)
- [Uso](#uso)
- [Modo -y](#modo--y)
- [Grupos y qué incluye cada uno](#grupos-y-qué-incluye-cada-uno)
- [Sobre ImageMagick](#sobre-imagemagick)
- [remove vs. purge](#remove-vs-purge)
- [Cómo revertirlo](#cómo-revertirlo)
- [Idempotencia](#idempotencia)
- [Licencia](#licencia)

---

## Qué hace

Las confirmaciones se piden con pantallas `whiptail` (Sí/No); si
`whiptail` no está instalado, el script lo instala antes de mostrar nada.
Tras las comprobaciones previas (no root, sistema APT, `sudo` disponible y
`sudo -v`), muestra una pantalla de bienvenida y revisa, **grupo por
grupo**, un conjunto de paquetes:

1. Comprueba qué paquetes de ese grupo están realmente instalados (si
ninguno lo está, pasa al siguiente grupo sin preguntar nada).
2. Te muestra la lista y pide confirmación específica de ese grupo.
3. Si confirmas, ejecuta `apt remove` (o `apt purge` con `--purge`) —
y salvo que uses `-y`, es el propio `apt` quien te enseña el resumen
real de la transacción (incluyendo cualquier dependencia que se lleve
por delante) antes de aplicar nada. Si contestas que no a esa
pregunta de `apt`, o `apt` falla, ese grupo se omite y el script
continúa con el siguiente.
4. Al final, opcionalmente, ejecuta `apt autoremove` para limpiar
paquetes huérfanos que hayan quedado sueltos, y `apt autoclean` para
limpiar del caché los `.deb` descargados de versiones que ya no
están disponibles en el repositorio.

## Por qué es un script aparte

`setup-debian-testing.sh` está pensado para *añadir* software de forma
predecible. Eliminar paquetes es una operación de naturaleza distinta:
la lista de "qué se lleva por delante" depende del estado de cada
sistema, y mezclar instalación y desinstalación en un mismo script hace
más peligroso volver a ejecutarlo en una máquina donde sí usas alguna de
estas apps. Por eso van separados.

## Uso

```bash
chmod +x cleanup-debian-testing.sh

# Modo interactivo (recomendado la primera vez): confirma cada grupo
./cleanup-debian-testing.sh

# Modo no interactivo: sin pantallas, confirma todos los grupos
./cleanup-debian-testing.sh -y

# Igual que el anterior, pero borrando también los ficheros de configuración
./cleanup-debian-testing.sh -y --purge

# Además, evalúa (con aviso) eliminar ImageMagick
./cleanup-debian-testing.sh --imagemagick

# Ayuda
./cleanup-debian-testing.sh -h
```

> Igual que en `setup-debian-testing.sh`: no lo ejecutes con
> `curl ... | bash` sin `-y`, porque las confirmaciones necesitan una
> entrada de terminal interactiva.

## Modo -y

Con `-y` no se muestra ninguna pantalla y se **confirman todos los
grupos** (no solo los "seguros"), usando `apt remove -y` (o
`apt purge -y` con `--purge`). Ten en cuenta:

- El aviso de KDE Partition Manager sobre `gnome-disk-utility` solo
aparece en las pantallas del modo interactivo. Con `-y`, se elimina
igualmente aunque `gnome-disk-utility` no esté instalado.
- Con `-y`, también se ejecuta `apt autoremove -y`, por lo que no queda
ninguna pregunta interactiva pendiente.
- Sin `-y`, el script requiere una terminal interactiva (TTY), porque las
confirmaciones se muestran con `whiptail`. En SSH, usa una sesión con
`ssh -t` o ejecuta el script con `-y` si realmente quieres modo no
interactivo.
- `-y` exporta `DEBIAN_FRONTEND=noninteractive` para que ningún paquete
se quede esperando una pantalla de `debconf` durante la eliminación.

## Grupos y qué incluye cada uno

| Grupo                                   | Paquetes                                                                                                                    | Notas                                                                                                                                                                                                    |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Suite PIM / Kontact                     | `kmail`, `kaddressbook`, `ktnef`, `kdepim-themeeditors`, `pim-sieve-editor`, `pim-data-exporter`, `korganizer`, `akregator` | Todos comparten árbol de dependencias con Akonadi (calendario y lector de RSS incluidos). `ktnef` es un paquete de transición que hoy en día vive dentro de `kmail`. `kdepim-themeeditors` es el paquete real detrás de "Editor de temas de Contact" **y** "Editor de temas de encabezados de KMail". |
| Accesibilidad                           | `kmousetool`, `kmouth`, `kontrast`                                                                                          | Independientes del grupo PIM: **no** se eliminan solos al quitar KMail, por eso van en grupo aparte.                                                                                                     |
| Konqueror                               | `konqueror`                                                                                                                 | Navegador/gestor de archivos histórico de KDE, sin relación con los otros grupos.                                                                                                                        |
| Dragon Player                           | `dragonplayer`                                                                                                             | Reproductor multimedia de KDE. Independiente de los grupos anteriores. |
| Juk                                      | `juk`                                                                                                                      | Reproductor/gestor de música de KDE. Independiente de los grupos anteriores. |
| xterm                                   | `xterm`                                                                                                                     | Emulador de terminal genérico de X11, no es una app de Plasma ni depende de los grupos anteriores; va en su propio grupo.                                                                                |
| KDE Connect                             | `kdeconnect`                                                                                                                | Integra el móvil con el escritorio (notificaciones, compartir archivos, control remoto...). Independiente de todos los grupos anteriores.                                                                |
| KDE Partition Manager                   | `partitionmanager`                                                                                                          | Se elimina porque `setup-debian-testing.sh` instala GNOME Disk Utility como alternativa. En modo interactivo, si `gnome-disk-utility` **no** está instalado, el script te avisa explícitamente antes de confirmar: si sigues adelante, te quedas sin gestor de particiones gráfico. |
| ImageMagick (opcional, `--imagemagick`) | `imagemagick`                                                                                                               | Ver aviso abajo.                                                                                                                                                                                         |

Antes de confirmar cada grupo, el script te enseña exactamente qué hay
instalado en tu sistema — siempre tienes la última palabra.

## Sobre ImageMagick

**No es una aplicación de Plasma.** Es una utilidad/librería de línea de
comandos que otros programas pueden usar por debajo (miniaturas,
importación/exportación de imágenes desde otras apps, scripts, etc.).
Por eso:

- No se evalúa a menos que pases `--imagemagick` explícitamente.
- Cuando se evalúa, el script primero ejecuta
`apt-cache rdepends imagemagick` y te enseña qué depende de él (las
primeras 15 líneas) **antes** de pedir confirmación. Con `-y` esa
pantalla no se muestra.

Si tienes dudas, dile que no cuando te pregunte y revisa el listado de
`rdepends` con calma en otro momento.

## remove vs. purge

- **`apt remove`** (por defecto): desinstala el paquete pero deja los
ficheros de configuración en `/etc` y en tu `$HOME` (por si algún día
reinstalas y quieres recuperar tu configuración).
- **`apt purge`** (con `--purge`): además borra esos ficheros de
configuración. Solo recomendable si tienes claro que no vas a volver a
usar esa app.

## Cómo revertirlo

Si más adelante echas en falta alguna de estas apps, se reinstala como
cualquier otro paquete:

```bash
sudo apt install kmail   # o el paquete que corresponda
```

Si usaste `apt remove` (no `--purge`), tu configuración anterior debería
seguir ahí.

## Idempotencia

Se puede volver a ejecutar sin problema: cada grupo comprueba primero qué
está instalado, así que si ya quitaste algo, el script simplemente te
dirá "nada que hacer" para ese grupo y seguirá con el siguiente. Los
paquetes que quedaron en estado `rc` (eliminados con `apt remove` pero
con configuración residual) se consideran ya eliminados y no se vuelven a
ofrecer.

Tras un `apt full-upgrade`, alguno de estos paquetes podría volver a
aparecer si otro paquete lo reintroduce como dependencia. Si pasa,
vuelve a ejecutar este script.

La documentación se mantiene alineada con el comportamiento actual del
script; antes de publicar una nueva versión conviene repetir una prueba
completa en una instalación limpia de Debian Testing.

## Licencia

MIT
