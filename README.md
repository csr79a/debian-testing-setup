# Debian Testing Setup

> **Este archivo es:** el README raíz del proyecto. Es el punto de
> entrada: aquí ves de un vistazo qué hace el proyecto completo, cómo
> está organizado y a qué otro archivo ir según lo que necesites.

Scripts para configurar un sistema **Debian Testing** con KDE Plasma:
repositorios, paquetes de desarrollo/multimedia/sistema/OCR, microcode,
Flathub, zram y limpieza de apps de KDE que no uses.

> **Antes de nada:** este proyecto asume que ya tienes un sistema Debian
> instalado con los repositorios apuntando a `testing`. No instala
> Debian por ti ni migra un sistema desde otra rama. Si algún
> repositorio de Debian apunta a otra suite (stable, unstable...),
> `setup-debian-testing.sh` se detiene: no convierte suites
> automáticamente.

Versiones documentadas: `setup-debian-testing.sh` 1.0.0 y
`cleanup-debian-testing.sh` 1.0.0.

---

## Estructura del proyecto

```
debian-testing-setup/
├── MANUAL.md              ← empieza por aquí si no sabes bash
├── README.md               (este archivo)
├── corregir-repos-testing.sh ← normaliza los repositorios Debian Testing
├── setup/
│   ├── setup-debian-testing.sh
│   └── README.md            ← detalle de qué instala
└── cleanup/
    ├── cleanup-debian-testing.sh
    └── README.md            ← detalle de qué elimina
```

**Guía rápida de qué archivo leer según lo que necesites:**

| Quieres...                                              | Lee...              |
| --------------------------------------------------------- | ---------------------- |
| Una visión general del proyecto                         | Este README (aquí)   |
| Corregir/normalizar los repositorios de Debian Testing  | `corregir-repos-testing.sh` |
| Instrucciones paso a paso, sin dar nada por sabido       | `MANUAL.md`           |
| El detalle técnico de qué instala `setup-debian-testing.sh` | `setup/README.md`     |
| El detalle técnico de qué elimina `cleanup-debian-testing.sh` | `cleanup/README.md`   |

## Uso rápido

Si acabas de instalar Debian Testing y quieres dejar los repositorios en el formato esperado por este proyecto, ejecuta primero `corregir-repos-testing.sh`. Después ejecuta `setup/setup-debian-testing.sh` para la configuración del sistema. El script de corrección escribe automáticamente las tres suites de la rama testing (`testing`, `testing-updates` y `testing-security`) y no convierte una instalación que apunte a otra rama: si detecta una suite que no sea de testing, se detiene.

```bash
chmod +x setup/setup-debian-testing.sh cleanup/cleanup-debian-testing.sh

cd setup && ./setup-debian-testing.sh        # configuración inicial
cd ../cleanup && ./cleanup-debian-testing.sh # limpieza de apps KDE (opcional, después)
```

Ambos scripts te van preguntando con pantallas de confirmación
(`whiptail`, que se instala solo si falta). La primera vez, úsalos sin
`-y`: el modo `-y` acepta todo automáticamente, incluidas operaciones
irreversibles (ver el detalle en `setup/README.md`).

Si es la primera vez que usas este proyecto, lee primero `MANUAL.md` —
explica paso a paso, sin asumir que sabes bash, cómo dejar `sudo` listo
y ejecutar ambos scripts con seguridad.

## Qué hace cada script

- **`setup/`** — comprueba que todos los repositorios de Debian apunten
a la rama de testing (`testing`, `testing-updates`, `testing-security`;
si no, se detiene, también con `-y`), escribe los
repos en formato deb822, `apt full-upgrade` opcional, microcode según
CPU, paquetes de desarrollo/multimedia/sistema/utilidades de disco/OCR
(Tesseract), fuentes de Windows y de Ubuntu, Flathub, zram con tamaño
calculado automáticamente según tu RAM (y `vm.swappiness` opcional), y
sustitución opcional de Firefox ESR por el Firefox oficial de Mozilla
(con verificación de huella GPG; instala Firefox primero y solo si eso
funciona elimina ESR y sus perfiles). El driver NVIDIA no se instala
desde este script. Detalle completo en [`setup/README.md`](setup/README.md).

- **`cleanup/`** — elimina, por grupos y con confirmación individual,
apps de KDE Plasma que Debian instala por defecto pero que muchos no
usan (suite PIM/Kontact, accesibilidad, Konqueror, xterm, KDE Connect,
KDE Partition Manager, e ImageMagick como grupo opcional). Detalle
completo en [`cleanup/README.md`](cleanup/README.md).

## Sobre la rama Testing

Testing es la rama de desarrollo de la **próxima versión estable** de
Debian. Se comporta de forma razonablemente estable la mayor parte del
ciclo (los paquetes suelen migrar desde Unstable tras cumplir los
criterios de migración; el retraso estándar es de 2, 5 o 10 días según la
urgencia, aunque las reglas cambian durante el freeze), pero:

- **No tiene cobertura de seguridad garantizada en plazos cortos.** El
  equipo de seguridad de Debian no gestiona testing de forma puntual;
  esa cobertura mejora según se acerca el *freeze* del ciclo. Si
  necesitas parches de seguridad con más garantía en algún paquete
  concreto, la documentación oficial de Debian recomienda apuntar
  temporalmente esa entrada a la suite de la stable actual.
- **Entra en *freeze* antes de cada lanzamiento**, durante varios
  meses: deja de recibir paquetes con funcionalidades nuevas, solo
  parches de errores aprobados por el equipo de release. Es normal
  notar que el ritmo de actualizaciones baja mucho en esa fase.

Estos dos puntos están documentados también dentro del propio script
(comentarios en `setup-debian-testing.sh` y en su resumen final).

## Licencia

MIT
