# setup/README.md — setup-debian-testing.sh

> **Este archivo es:** el detalle técnico de `setup-debian-testing.sh`
> (el script que **instala/configura**). Léelo cuando quieras saber
> exactamente qué hace cada paso, qué paquetes instala o cómo funciona
> la comprobación de suites. Para el script que **elimina** apps, ve a
> `cleanup/README.md`. Para una guía paso a paso sin dar nada por
> sabido, ve a `MANUAL.md` en la raíz del proyecto.

Configura un sistema **Debian Testing** recién instalado con KDE
Plasma: repositorios en formato deb822 apuntando a `testing`,
actualización del sistema, un set de paquetes de desarrollo/multimedia/
sistema/utilidades de disco/OCR, microcode de CPU, fuentes de Windows y
de Ubuntu, Flathub, zram y, de forma opcional, Firefox oficial de
Mozilla. Es el complemento de `cleanup-debian-testing.sh`: este script
instala, aquel quita.

> Este script **no instala Debian** ni migra un sistema desde otra
> rama. Asume que ya tienes un Debian funcionando con los repos
> apuntando a `testing`.

> El driver NVIDIA **no** se instala desde este script (gestión
> pendiente de decidir en un proyecto aparte).

Versión documentada: **1.0.0**.

---

## Índice

- [Qué hace](#qué-hace)
- [Uso](#uso)
- [Modo -y: qué acepta automáticamente](#modo--y-qué-acepta-automáticamente)
- [Comprobación de suites](#comprobación-de-suites)
- [Repositorios](#repositorios)
- [Sobre la seguridad en Testing](#sobre-la-seguridad-en-testing)
- [Paquetes que instala](#paquetes-que-instala)
- [Microcode](#microcode)
- [Fuentes de Windows y de Ubuntu (opcional)](#fuentes-de-windows-y-de-ubuntu-opcional)
- [Flathub](#flathub)
- [Zram automático](#zram-automático)
- [Firefox oficial de Mozilla (opcional)](#firefox-oficial-de-mozilla-opcional)
- [Driver NVIDIA](#driver-nvidia)
- [Idempotencia](#idempotencia)
- [Licencia](#licencia)

---

## Qué hace

Las decisiones se piden con pantallas `whiptail` (Sí/No); el progreso de
`apt` y del resto de comandos largos se muestra como texto normal de
terminal.

1. Comprueba que no estés ejecutando el script como root, que el sistema
use APT y que `sudo` funcione (`sudo -v`). Si falta `whiptail`, lo
instala antes de mostrar nada.
2. Detecta el fabricante de CPU (Intel/AMD) para el paso de microcode.
3. Muestra la pantalla de bienvenida y, a título informativo, el
codename de Testing detectado en `/etc/os-release` (ese campo sí es
fiable en Testing; no se pide confirmación manual por esto).
4. **Comprueba las suites de todos los repositorios de Debian** y se
detiene si alguno apunta a algo distinto de `testing` (ver
[Comprobación de suites](#comprobación-de-suites)).
5. Si detecta contenido activo en el `/etc/apt/sources.list` clásico
(típico de una instalación fresca, que por defecto apunta a la stable
actual), pide confirmación, hace una copia de seguridad y lo comenta,
para evitar repos duplicados con el nuevo fichero deb822.
6. Escribe `/etc/apt/sources.list.d/debian.sources` apuntando solo a
`testing`. Si el fichero ya existe, no lo sobrescribe.
7. Actualiza índices (`apt update`) y, si confirmas, hace
`apt full-upgrade`. Si falla, solo continúa cuando `dpkg` queda en un
estado consistente.
8. Instala la lista de paquetes, agrupados en bloques independientes
(ver tabla abajo), incluyendo el microcode correspondiente a tu CPU.
9. Pregunta si instalar fuentes de Windows (`ttf-mscorefonts-installer`)
y de Ubuntu (`fonts-ubuntu`).
10. Añade el remoto de Flathub si no estaba ya configurado.
11. Propone configurar zram con un tamaño calculado automáticamente
según tu RAM, y opcionalmente ajustar `vm.swappiness`.
12. Opcionalmente, sustituye Firefox ESR por el Firefox oficial de
Mozilla, verificando la huella digital de su clave GPG. **Elimina
Firefox ESR y todos sus perfiles y datos.**
13. Imprime un resumen con notas y avisos propios de Testing (ver
[Sobre la seguridad en Testing](#sobre-la-seguridad-en-testing)). Si
detecta una GPU NVIDIA por `lspci`, solo te avisa; no instala nada.

## Uso

```bash
chmod +x setup-debian-testing.sh

# Modo interactivo (recomendado la primera vez)
./setup-debian-testing.sh

# Modo no interactivo: acepta TODAS las preguntas (ver sección siguiente)
./setup-debian-testing.sh -y

# Ayuda
./setup-debian-testing.sh -h
```

> No lo ejecutes con `curl ... | bash` sin `-y`: las confirmaciones
> necesitan una entrada de terminal interactiva.

## Modo -y: qué acepta automáticamente

Con `-y` no se muestra ninguna pantalla y **se aceptan todas las
preguntas**, incluidas operaciones destructivas. El propio script lo
avisa al arrancar. En concreto:

- comentar el contenido activo de `/etc/apt/sources.list` (con copia de
seguridad previa);
- eliminar Firefox ESR, `/etc/firefox-esr` y **todos** sus perfiles y datos
(`~/.mozilla/firefox`), de forma **irreversible**;
- configurar zram y ajustar `vm.swappiness` (sysctl);
- aceptar automáticamente la licencia (EULA) de las fuentes de Windows.

Además, `-y` exporta `DEBIAN_FRONTEND=noninteractive`, lo que silencia
todos los avisos de `debconf` durante las instalaciones.

Lo que **no** se salta con `-y` son las comprobaciones críticas: si los
repositorios configurados no son Debian Testing, el script se detiene.

## Comprobación de suites

Este script **solo trabaja con Testing**. Antes de continuar con
`apt update` y `apt full-upgrade`, revisa:

- `/etc/apt/sources.list.d/debian.sources`
- el `/etc/apt/sources.list` clásico
- el resto de ficheros `*.sources` y `*.list` de `/etc/apt/sources.list.d`
que apunten a Debian

Se aceptan **`testing`** y **`testing-security`** siempre. Además, el
codename del sistema (por ejemplo `forky`) y `<codename>-security` se
aceptan **solo si `/etc/os-release` confirma que el sistema es testing**
(`PRETTY_NAME` con `/sid`, o `/etc/debian_version` acabado en `/sid`).
Así, cuando ese codename pase a stable, dejará de aceptarse solo. Las
suites de testing que no se configuran (`testing-updates`,
`testing-proposed-updates`, `testing-backports` y sus equivalentes con el
codename) no detienen el script. Cualquier otra rama (`stable`, `sid`,
`bookworm`, `trixie`...) **detiene el script**, también con `-y`: es una
comprobación de seguridad, no una pregunta, y no se convierte a Testing;
hay que corregirla o desactivarla a mano.

Una entrada cuenta como "de Debian" si su URI es de `debian.org` o si usa
`debian-archive-keyring` como clave, así que los repositorios de terceros
(Docker, Brave...) no se marcan. Se ignoran las entradas de `cdrom:` y las
marcadas con `Enabled: no`. Limitación: un mirror con dominio propio y sin
`debian-archive-keyring` no se reconoce como Debian.

## Repositorios

Formato deb822, en `/etc/apt/sources.list.d/debian.sources` (solo se crea
si no existe), con `testing` y `testing-security`:

```
Types: deb
URIs: https://deb.debian.org/debian
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: testing-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
```

No se añaden `testing-updates` ni `testing-backports`: la primera está
pensada para actualizaciones puntuales y no aporta paquetes en testing; la
segunda está orientada a las ramas stable.

## Sobre la seguridad en Testing

A diferencia de la stable actual, **testing no tiene garantizada una
cobertura de seguridad puntual** por parte del equipo de seguridad de
Debian; esa cobertura mejora conforme se acerca el *freeze* del ciclo,
pero no es equiparable a la de una versión stable en ningún momento del
ciclo. La propia documentación oficial de Debian lo indica
explícitamente y recomienda, si necesitas parches de seguridad
garantizados en algún paquete concreto, apuntar temporalmente esa
entrada a la suite de la stable actual mientras dure la necesidad.

El script no automatiza ese cambio de suite (decidir a qué stable
apuntar, y solo para qué paquetes, es una decisión que depende del
momento y de cada caso), pero lo deja documentado aquí y en el resumen
final para que lo tengas presente.

## Paquetes que instala

Se instalan en bloques independientes (11 con microcode):

| Categoría                        | Paquetes                                                                                                                                     |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Control de versiones / descargas | `git`, `git-lfs`, `curl`, `wget`                                                                                                             |
| Compresión                       | `unzip`, `zip`, `7zip` (o `p7zip-full` si `7zip` no está disponible en tus repos)                                                            |
| Sistema / diagnóstico            | `btop`, `fastfetch`, `tree`, `jq`, `ripgrep`, `fd-find`, `pciutils`, `usbutils`, `lshw`, `dmidecode`, `inxi`, `hwinfo`, `lm-sensors`, `acpi` |
| Utilidades de disco               | `gnome-disk-utility` (gestión gráfica de discos/particiones, comando `gnome-disks`)                                                          |
| Desarrollo / compilación         | `build-essential`, `gcc`, `g++`, `make`, `cmake`, `ninja-build`, `pkg-config`, `autoconf`, `automake`, `libtool`, `openssh-client`           |
| Multimedia                       | `ffmpeg`, `gstreamer1.0-libav`, `gstreamer1.0-plugins-good/bad/ugly`, `pavucontrol`                                                          |
| Firmware                         | `firmware-linux` (metapaquete; usa `lspci -k` si prefieres algo más quirúrgico)                                                              |
| Gestión de paquetes (GUI)        | `synaptic`                                                                                                                                    |
| Flatpak + integración KDE        | `flatpak`, `plasma-discover-backend-flatpak`                                                                                                 |
| OCR (capturas de pantalla)       | `tesseract-ocr`, `tesseract-ocr-eng`, `tesseract-ocr-spa`, `tesseract-ocr-osd`                                                               |
| Microcode                        | `intel-microcode` o `amd64-microcode`, según la CPU detectada                                                                                |

El grupo **OCR** instala el motor Tesseract con datos de inglés, español y
detección de orientación, para poder extraer texto de las capturas de
pantalla desde Spectacle. Comprueba los idiomas disponibles con
`tesseract --list-langs`.

El paquete `7zip` es relativamente nuevo en el archivo de Debian. El
script comprueba con `apt-cache show 7zip` si está disponible en tus
repos antes de intentar instalarlo; si no lo está, usa `p7zip-full` como
alternativa, para que un único paquete no encontrado no haga fallar toda
la instalación.

Los paquetes se instalan por bloques independientes: si uno falla, se
avisa, se continúa con el resto en vez de abortar toda la instalación, y
el resumen final lista los grupos que fallaron para que los reintentes a
mano. Si falla el grupo que incluye `wget` o `pciutils`, los pasos que
los necesitan (Firefox, detección de NVIDIA) intentan instalarlos por
separado o se omiten con un aviso.

## Microcode

Se lee `vendor_id` de `/proc/cpuinfo`:

- `GenuineIntel` → `intel-microcode`
- `AuthenticAMD` → `amd64-microcode`
- Cualquier otro valor → se avisa y no se instala ningún paquete de
microcode automáticamente.

Debian solo distribuye microcode genérico por fabricante, no por modelo
de CPU. El modelo que se muestra en pantalla es solo informativo.

## Fuentes de Windows y de Ubuntu (opcional)

Dos preguntas independientes:

- **Fuentes de Windows** (`ttf-mscorefonts-installer`): Arial, Times New
Roman, Courier New, etc. El paquete descarga los `.ttf` originales de
Microsoft en tiempo de instalación y requiere aceptar su licencia
(EULA). En modo `-y`, el script acepta la licencia automáticamente vía
`debconf-set-selections`; en modo interactivo puede que veas también la
pantalla de aceptación propia de `debconf`. Si la descarga falla (los
servidores externos a veces caen), se avisa y se continúa.
- **Fuentes de Ubuntu** (`fonts-ubuntu`): empaquetadas tal cual en los
repos oficiales de Debian, sin pasos adicionales.

## Flathub

Añade el remoto `flathub` (a nivel de sistema) si no existe ya, para
poder instalar Flatpaks desde Discover (KDE Plasma) o desde la línea de
comandos. Si Flatpak no está instalado (porque falló su grupo de
paquetes), este paso se omite con un aviso.

## Zram automático

El tamaño de zram (swap comprimido en RAM) se calcula **automáticamente** a partir de la RAM total del sistema, usando la regla práctica de "la
mitad de la RAM":

| RAM total detectada | Zram configurado |
| -------------------- | ------------------ |
| 8 GB                 | 4 GB               |
| 16 GB                | 8 GB               |
| 32 GB                | 16 GB              |

El script lee `/proc/meminfo` en tiempo de ejecución, así que el cálculo
se adapta a la máquina real donde se ejecute — no hay que tocar nada a
mano. Antes de aplicarlo, te muestra la RAM detectada y el tamaño
propuesto, y sigue pidiendo confirmación como el resto de pasos. Si por
algún motivo no se puede leer `/proc/meminfo`, se omite este paso en vez
de aplicar un tamaño inválido.

Para aplicarlo, instala `zram-tools` si hace falta, hace una copia de
seguridad de `/etc/default/zramswap` (`.bak.<fecha>`), detecta si el
fichero usa `SIZE` o `ALLOCATION`, comenta las líneas `PERCENT` o
`PERCENTAGE` y escribe el tamaño en MiB. Después reinicia el servicio
`zramswap`. Si no reconoce el formato del fichero, no lo toca y te remite
a la [wiki de Debian](https://wiki.debian.org/ZRam).

Tras configurar zram, el script también ofrece ajustar `vm.swappiness` a
**130** (con confirmación aparte). Por defecto el kernel usa `60`, un
valor pensado para cuando el swap vive en disco: el kernel espera a que
la RAM esté casi llena antes de usarlo, porque escribir en disco es
lento. Con zram el "swap" vive comprimido en la propia RAM, mucho más
rápido, así que conviene un valor más alto (el rango habitual
recomendado con zram es 130-180) para que el kernel mande antes las
páginas frías al zram y deje más RAM libre real para caché y procesos
activos. El ajuste se guarda de forma persistente en
`/etc/sysctl.d/99-zram-swappiness.conf`.

## Firefox oficial de Mozilla (opcional)

Debian solo empaqueta `firefox-esr` en su archivo oficial (no distribuye
la versión release por su política de marca), también en Testing. El
orden de este paso es deliberado: primero todo lo **no destructivo**
(clave, repositorio e instalación de Firefox normal), y solo si eso
termina bien se elimina ESR. Así, un fallo de red, de verificación o de
instalación no deja el equipo sin navegador ni sin perfil.

Si aceptas este paso (la pantalla de confirmación avisa de que es
irreversible):

1. El script detecta qué paquetes de ESR están instalados
(`firefox-esr` y `firefox-esr-l10n-es`).
2. Descarga la clave GPG de Mozilla (necesita `wget` y `gpg`; instala
`gnupg` si falta) y **verifica su huella digital** contra el valor
oficial (`35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`) antes de confiar
en el repositorio. Si no coincide, se aborta este paso y se borra la
clave descargada.
3. Añade `/etc/apt/sources.list.d/mozilla.sources` (deb822) y un pin de
prioridad 1000 (`/etc/apt/preferences.d/mozilla`) para los paquetes
de ese origen, de modo que Firefox de Mozilla tenga preferencia sobre
cualquier paquete `firefox*` de Debian. Ejecuta `apt update`.
4. Intenta instalar `firefox` directamente con `apt install -y firefox`.
No se usa `apt-cache policy` como comprobación previa: puede dar un
falso negativo (sin candidato visible) aunque la instalación real
funcione bien, así que la única forma fiable de saber si Firefox de
Mozilla está disponible es intentar instalarlo de verdad. Si la
instalación tiene éxito, después ofrece el paquete de idioma español,
detectado dinámicamente: usa el primero disponible entre
`firefox-l10n-es-es`, `firefox-l10n-es-mx`, `firefox-l10n-es-ar` y
`firefox-l10n-es`, ya que Mozilla distribuye variantes regionales.
5. **Solo si esa instalación tuvo éxito**, elimina Firefox ESR con
`apt purge` (más un `apt autoremove -y`) y borra los restos de
`/etc/firefox-esr`. Si el `purge` falla, no se toca ni
`/etc/firefox-esr` ni ningún perfil, y el resumen final te dice cómo
reintentarlo. Si la instalación de Firefox normal falla, ESR y sus
perfiles no se tocan en absoluto.
6. Si el `purge` de ESR terminó bien, **borra por completo
`~/.mozilla/firefox`** (marcadores, contraseñas, historial, extensiones
y todos los perfiles que hubiera ahí). Es irreversible y no hay una
segunda pregunta: la confirmación inicial (o `-y`) lo cubre. Si Firefox
ESR **no** estaba instalado al empezar (por ejemplo, en una reejecución
del script), no se borra ningún perfil: lo que haya ya pertenece al
Firefox normal.

Firefox normal empieza con un perfil limpio: no se migran ni se
conservan datos de ESR.

> **AutoFirma:** su instalador inyecta el certificado raíz directamente
> dentro de la carpeta de cada perfil de Firefox que exista en ese
> momento (vía `certutil`, en el almacén NSS del perfil). Si instalas o
> reinstalas AutoFirma **después** de este paso, el certificado va al
> perfil release nuevo sin conflicto. Si AutoFirma ya estaba instalado
> sobre un perfil ESR que este script borra, el certificado se pierde
> con esa carpeta y hay que forzar a AutoFirma a reinyectarlo con
> el procedimiento de AutoFirma que utilizaste originalmente para volver a inyectar el certificado en el nuevo perfil.

## Driver NVIDIA

Este script **no** instala el driver NVIDIA, `switcheroo-control` (GPU
híbrida) ni ningún wrapper de offload. Si `lspci` detecta una GPU
NVIDIA, el resumen final solo te avisa de ello; no instala nada por ti.
La gestión del driver NVIDIA para este proyecto queda pendiente de
decidir.

## Idempotencia

El script se puede volver a ejecutar sin duplicar trabajo:

- No sobrescribe `/etc/apt/sources.list.d/debian.sources` si ya existe.
- Comprueba si Flathub ya está configurado antes de añadirlo. Los
ficheros del repositorio de Mozilla y sus pines de APT se reescriben
enteros con el mismo contenido, así que no se duplican.
- Detecta si `zram-tools` o Firefox ESR ya están en el estado esperado;
en particular, si ESR ya no está instalado, no se borra ningún perfil
de Firefox.

La documentación se mantiene alineada con el comportamiento actual del
script; antes de publicar una nueva versión conviene repetir una prueba
completa en una instalación limpia de Debian Testing.

## Licencia

MIT
