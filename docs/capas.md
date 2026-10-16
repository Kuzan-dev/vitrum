# Capas del instalador

Todas siguen el mismo patrón: `--dry-run` muestra el plan («CAMBIARÍA: …») sin tocar nada; sin él, el plan se
muestra, se pide confirmación (o `--yes`), se hace una copia o snapshot previo, se aplica y se **verifica**
(una segunda simulación debe dar 0 cambios). Cada paso compara antes de escribir: dos ejecuciones seguidas
dejan el mismo resultado.

## check (solo lectura)
Versiones validadas (Fedora 44 / GNOME 50), Wayland, UEFI, Secure Boot, btrfs, Snapper, RPM Fusion, espacio,
red; NVIDIA (origen del driver, paquete = módulo = `nvidia-smi`, extensión GL de Flatpak); monitores y HDR,
DDC/CI; ESP y entradas del firmware; herramientas de la capa de usuario; `config/local.env`.
`--sugerir` imprime los valores detectados para `local.env`.

## system (sudo)
`scripts/system/`: 00 dependencias (p. ej. `patch`), 01 snapshot de seguridad de btrfs (solo lectura),
02 Snapper (config «root», sin timeline, 10 snapshots, pre/post en cada transacción de dnf5), 03
`installonly_limit=4`, 04a RPM Fusion (paquetes release firmados; el driver NVIDIA excluido de los repos
generales), 04b ffmpeg completo, 04c paquetes multimedia de RPM Fusion, 05 grub-btrfs (submenú «Fedora
snapshots» en GRUB, tag + sha256), 07 regeneración automática del submenú al cambiar los snapshots.

## nvidia (sudo)
Solo comprobaciones y, si el driver requerido está instalado, VA-API (`libva-nvidia-driver`). Nunca instala ni
cambia el driver.

## gaming (sudo)
Steam (RPM de RPM Fusion), GameMode, MangoHud, vulkan-tools. Aborta si la transacción tocara el driver NVIDIA.

## login (sudo)
HDR en la pantalla de acceso: copia el `~/.config/monitors.xml` de quien instala a `/etc/xdg/monitors.xml` si
tiene HDR (validado con `xmllint`; el anterior se guarda como `.bak-<fecha>`). Sin HDR, se salta. Repetir tras
cambiar monitores, frecuencia o HDR.

## user (sin sudo, como el propio usuario)
`scripts/visual.sh`, en orden: tema GTK MacTahoe-Dark, iconos y cursores, GTK4 mínimo; extensiones fijadas
(con sus parches) y ajustes de Dash to Dock; barra (Just Perfection, Logo Menu, brillo por DDC); cristal de barra
y dock (Blur my Shell; variante en `config/visual/glass/variant`); tema de la shell GoldenGate (plantilla +
`tokens.env`; bandeja «dentro» o «propia» en `shell-theme/tray/variant`); fondo Series of Tubes; desactivación
del escaneo directo de Mutter (`environment.d`, evita el parpadeo del dock en el segundo monitor tras cambiar de
usuario con NVIDIA); bandeja de iconos (AppIndicator). Color de acento: `ACCENT_COLOR` de `local.env`.
Copia previa en `~/.local/state/dotfiles/copias/` (se conservan 3). Cierra sesión y vuelve a entrar al terminar.

### Opcional: fondo animado (`--waywallen`)
Waywallen (Flatpak de usuario de Flathub, fijado por commit y enmascarado, ~3 GB con runtimes) y su extensión.
Perfil «abierto»: red, GPU, audio, MPRIS, GameMode y solo lectura de `~/.local/share/Steam/steamapps`; nunca la
carpeta `config/` de Steam. `--wallpaper-engine` añade open-wallpaper-engine y la biblioteca de Steam (Steam y
Wallpaper Engine los instalas tú; no hace falta iniciar sesión de Steam en Waywallen). `--medios-prueba` genera
vídeos de prueba propios. Pausa automática al maximizar, a pantalla completa y con GameMode.

## boot (opt-in; nunca en `all`)
rEFInd por encima de GRUB con el tema rEFInd-lite (fondo negro). Copia de la ESP y de `efibootmgr -v`, plan con
los PARTUUID de `local.env` (Windows opcional), confirmación, carpeta nueva + renombrado (la anterior queda como
`refind.old`), entrada en el firmware **sin cambiar BootOrder** y `BootNext` para probar. Tras arrancar bien:
`./install.sh boot --fijar-orden` (rEFInd primero, Fedora justo detrás).
