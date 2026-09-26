# Manual — Scripts de configuración para Debian Testing

> **Este archivo es:** la guía paso a paso, pensada para alguien que no
> conoce bash a fondo. No asume que sepas qué es `sudo`, cómo dar
> permisos de ejecución a un archivo, ni nada parecido: cada comando
> viene explicado. Si ya manejas la terminal con soltura y solo quieres
> el detalle técnico de qué hace cada script, ve directamente a
> `setup/README.md` o `cleanup/README.md`.

Este manual te lleva de la mano por todo el proceso: dejar `sudo`
listo, copiar los scripts al sistema, darles permiso de ejecución y
ejecutarlos con seguridad.

---

## 1. Antes de nada: deja `sudo` listo

Los scripts necesitan ejecutar comandos con privilegios de
administrador (instalar paquetes, escribir en `/etc`, etc.), y lo hacen
a través de `sudo`, nunca ejecutándose directamente como root. Si tu
usuario ya puede usar `sudo` (lo normal si instalaste Debian marcando
la opción de crear un usuario administrador), puedes saltar a la
[sección 2](#2-descargarcopiar-los-scripts-y-darles-permiso-de-ejecución).

Si tu usuario **no** tiene `sudo` todavía, hazlo así:

```bash
# 1. Entra como root (te pedirá la contraseña de root)
su -

# 2. Instala sudo
apt update && apt install sudo

# 3. Añade tu usuario normal al grupo sudo (sustituye TU_USUARIO)
usermod -aG sudo TU_USUARIO

# 4. Sal de la sesión de root
exit
```

Después, **cierra sesión y vuelve a entrar** (o reinicia) para que el
cambio de grupo surta efecto. Comprueba que funciona con:

```bash
sudo -v
```

Si te pide tu contraseña (la tuya, no la de root) y no da ningún error,
ya está listo.

## 2. Descargar/copiar los scripts y darles permiso de ejecución

Copia la carpeta completa del proyecto a tu sistema (USB, `git clone`,
`scp`, lo que uses):

```bash
# copia aquí la carpeta "debian-testing-setup" completa
cd ~/Documentos/debian-testing-setup
chmod +x setup/setup-debian-testing.sh cleanup/cleanup-debian-testing.sh
```

`chmod +x` da permiso de ejecución a los dos scripts. Comprueba que
quedó bien:

```bash
ls -l setup/setup-debian-testing.sh cleanup/cleanup-debian-testing.sh
```

Deberías ver algo como:

```
-rwxr-xr-x ...   ← las "x" indican que ya es ejecutable
```

## 3. Ejecutar los scripts

```bash
# Configuración inicial del sistema (asume que ya apuntas a testing)
cd setup
./setup-debian-testing.sh

# Limpieza de apps de KDE que no usas (ejecútalo después, cuando quieras)
cd ../cleanup
./cleanup-debian-testing.sh
```

La primera vez, ejecuta ambos **sin** `-y`: cada paso te lo pregunta con
una pantalla, y así puedes decidir qué instalar/eliminar y qué no.

### Modo no interactivo (`-y`)

Una vez que ya conoces el script y sabes lo que hace, puedes usar `-y`
para que no te pregunte nada y acepte todo automáticamente:

```bash
./setup-debian-testing.sh -y
```

**Importante:** con `-y`, `setup-debian-testing.sh` también acepta
operaciones irreversibles sin preguntar, en concreto:

- comentar el contenido de `/etc/apt/sources.list` (con copia de
  seguridad previa, eso sí);
- eliminar Firefox ESR y **todos** sus perfiles/datos
  (marcadores, contraseñas, historial);
- configurar zram y ajustar `vm.swappiness`.

Si no estás seguro de querer todo eso automáticamente, usa el modo
interactivo (sin `-y`) al menos la primera vez.

### Ayuda

Ambos scripts tienen su propia ayuda integrada:

```bash
./setup-debian-testing.sh -h
./cleanup-debian-testing.sh -h
```

## 4. Sobre el zram automático

`zram` es una forma de "swap" (memoria de intercambio) que vive
comprimida dentro de la propia RAM, en vez de en el disco. Es mucho más
rápido que el swap tradicional en disco y ayuda a que el sistema no se
quede sin memoria en momentos de mucho uso.

El script calcula el tamaño automáticamente: **la mitad de tu RAM
total**. Por ejemplo, con 32 GB de RAM, configurará 16 GB de zram. No
tienes que decidir nada, solo confirmar cuando te lo pregunte.

También te preguntará si quieres ajustar `vm.swappiness` (un parámetro
del kernel que decide cuánto "le gusta" usar el swap) a un valor más
alto de lo normal, porque con zram conviene que el sistema lo use antes
que con swap en disco.

## 5. Sobre la migración de Firefox y AutoFirma

Debian, también en Testing, solo trae Firefox ESR (la versión de
soporte extendido) en sus repositorios oficiales. Si quieres la versión
normal (release) de Mozilla, el script te ofrece:

1. Añadir el repositorio oficial de Mozilla (verificando su clave
   digital, para que no te la puedan falsificar).
2. Instalar Firefox normal.
3. **Solo si eso funciona bien**, eliminar Firefox ESR y todos sus
   datos.

Si usas **AutoFirma** (certificado FNMT para trámites de la
administración), ten en cuenta: AutoFirma mete su certificado dentro de
la carpeta del perfil de Firefox que tengas en ese momento. Si instalas
o reinstalas AutoFirma **después** de migrar a Firefox normal, no hay
problema. Pero si AutoFirma ya estaba metido en un perfil de Firefox ESR
que este script borra, el certificado se pierde con ese perfil, y
tendrás que reinstalar/reinyectarlo:

```bash
sudo apt reinstall autofirma
```

## 6. Orden recomendado

1. `setup-debian-testing.sh` (sin `-y` la primera vez), para dejar el
   sistema base configurado.
2. Revisa que todo haya ido bien (lee el resumen final que imprime el
   propio script).
3. Si quieres, `cleanup-debian-testing.sh`, para quitar las apps de KDE
   que no uses.
4. Reinicia si el script te lo indica (por ejemplo, tras cambios de
   microcode/firmware).

## 7. Si algo sale mal

- **El script se detiene diciendo que tus repositorios no apuntan a
  `testing`:** es la comprobación de seguridad funcionando como debe.
  Revisa `/etc/apt/sources.list` y
  `/etc/apt/sources.list.d/debian.sources`: si hay líneas activas
  apuntando a otra rama (por ejemplo `trixie`, típico en una
  instalación fresca), coméntalas a mano antes de volver a ejecutar el
  script. Ejemplo:

  ```bash
  sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)
  sudo sed -i -E '/^[[:space:]]*deb(-src)?[[:space:]]/ s/^/# /' /etc/apt/sources.list
  ```

- **Un grupo de paquetes falla al instalar:** el script te avisa cuál
  falló y continúa con el resto. Al final tienes el comando exacto para
  reintentarlo a mano.

- **`apt full-upgrade` falla:** el script comprueba con
  `sudo dpkg --audit` si el sistema quedó en un estado inconsistente.
  Si es así, se detiene y te pide resolverlo antes de continuar (con
  `sudo dpkg --configure -a` y `sudo apt -f install`, típicamente). Si
  `dpkg` está consistente, el script sigue con el resto de pasos y te
  recuerda resolver el `full-upgrade` más tarde.

- **Quieres deshacer algo que el script cambió:** revisa las copias de
  seguridad que hace antes de tocar nada (`/etc/apt/sources.list.bak.*`,
  `/etc/default/zramswap.bak.*`, etc.). Están fechadas, así que puedes
  identificar la más reciente antes del cambio que quieres revertir.

## Licencia

MIT
