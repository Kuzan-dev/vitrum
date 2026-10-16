# vitrum

Escritorio GNOME inspirado en macOS para **Fedora Workstation 44 / GNOME 50**, instalable de forma
reproducible: tema, extensiones fijadas por versión y sha256, barra y dock de cristal, bandeja de iconos,
fondo animado opcional, Snapper con snapshots en GRUB, códecs, gaming y, opcionalmente, rEFInd.

> **Estado: pre-release.** Probado solo en un equipo (GPU NVIDIA reciente, dos monitores, uno con HDR) y en
> una VM de Fedora 44. **No probado en otro hardware.**

## Requisitos

- **Fedora Workstation 44 con GNOME 50** (Wayland), UEFI y raíz en **btrfs** (la instalación por defecto).
  `install.sh` se niega a continuar en otras versiones salvo con `--forzar-version`.
- **GPU NVIDIA**: el driver debe estar **ya instalado** desde el repositorio de terceros de Fedora
  `rpmfusion-nonfree-nvidia-driver` (`akmod-nvidia`), con el módulo construido y cargado (y la clave MOK inscrita
  si usas Secure Boot). El instalador lo comprueba y avisa, pero **no instala ni cambia el origen del driver**.
  Sin NVIDIA, las partes de NVIDIA se saltan.
- Conexión a internet (descargas fijadas por versión y sha256).

## Aviso

- **Lee el código antes de ejecutarlo.** Las capas de sistema usan **sudo** y modifican `/etc` y paquetes (dnf);
  cada capa muestra su plan, pide confirmación, crea un snapshot de Snapper y se verifica al terminar.
- Empieza siempre por `./install.sh check` (solo lectura) y `./install.sh all --dry-run`.
- Cambios de sistema a tener en cuenta:
  - **HDR en la pantalla de acceso** (capa login): copia tu `~/.config/monitors.xml` a `/etc/xdg/monitors.xml`.
  - **Escaneo directo de Mutter desactivado** (capa user, `~/.config/environment.d`): evita un parpadeo del dock
    con NVIDIA y dos monitores, a cambio de que las apps a pantalla completa pasen siempre por el compositor.
- **La capa de arranque (`install.sh boot`, opcional) toca la partición EFI y el firmware: un error puede dejar el
  equipo sin arrancar.** Ten a mano un USB de Fedora y lee `docs/vuelta-atras.md` antes de usarla.
- Úsalo bajo tu responsabilidad (ver `LICENSE`).

## Instalación

```
git clone --depth 1 --branch <versión> https://github.com/Kuzan-dev/vitrum ~/vitrum
cd ~/vitrum
./install.sh check --sugerir > config/local.env   # revisa los valores detectados
./install.sh check                                 # solo lectura: qué aplica y qué falta
./install.sh all --dry-run                         # simulación de todo
./install.sh all                                   # system → nvidia → gaming → login → user
```

Usa siempre una versión etiquetada (`--branch vX.Y`). Al terminar, cierra sesión y vuelve a entrar.

- Capas sueltas: `./install.sh system|nvidia|gaming|login|user [--dry-run] [--yes]`.
- Fondo animado (opcional): `./install.sh user --waywallen` instala Waywallen (Flatpak de Flathub, ~3 GB);
  `--wallpaper-engine` añade open-wallpaper-engine para los fondos de Wallpaper Engine de tu Steam (Steam y
  Wallpaper Engine no se instalan). Ver `docs/capas.md`.
- rEFInd (opcional, nunca dentro de `all`): `./install.sh boot`, y tras arrancar bien `./install.sh boot --fijar-orden`.
- Comprobación: `./install.sh verify user`; las capas de sistema se comprueban con `--dry-run` (0 cambios).

Qué hace cada capa: `docs/capas.md`. Vuelta atrás y rescate: `docs/vuelta-atras.md`. Reinstalar desde
cero: `docs/restauracion.md`.

## Valores propios del equipo

`config/local.env` (no se publica; plantilla en `config/local.env.example`): usuarios, PARTUUID de las ESP,
entrada de Fedora en el firmware, color de acento y, solo para el escaneo de datos personales, series de
monitores, correos e IP. `./install.sh check --sugerir` los detecta.

## Desarrollo

- Hooks de pre-commit y commit-msg: `git config core.hooksPath tools/hooks` (bloquean los valores de
  `local.env` y patrones de secretos). CI: `shellcheck` y escaneo genérico (`.github/workflows/`).
- VM de pruebas: `tools/vm/vm-prueba.sh` (Fedora 44 por kickstart, UEFI, btrfs; sin root).

## Licencia y atribuciones

Código propio bajo **GPL-3.0-or-later** (`LICENSE`). Los parches de extensiones conservan la licencia de su
extensión. Componentes de terceros, licencias y fondos: `ATRIBUCIONES.md`.
