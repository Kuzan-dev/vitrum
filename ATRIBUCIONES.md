# Atribuciones y licencias

El código propio de este repositorio (scripts, plantillas, configuración) se publica bajo **GPL-3.0-or-later**.
Los componentes de terceros **no se incluyen ni se redistribuyen** (ni tarballs ni fondos): el instalador los descarga en versiones fijadas (commit y sha256,
`config/visual/pins.env` y scripts) y conservan sus licencias.

## Descargados al instalar

| Componente | Autor / origen | Licencia |
|---|---|---|
| MacTahoe GTK theme | vinceliuice/MacTahoe-gtk-theme | MIT |
| MacTahoe icon theme (iconos y cursores) | vinceliuice/MacTahoe-icon-theme | GPL-3.0 |
| Dash to Dock | micheleg/dash-to-dock (extensions.gnome.org) | GPL-2.0 |
| Blur my Shell | aunetx/blur-my-shell | GPL-3.0 |
| Just Perfection | jrahmatzadeh/just-perfection | GPL-3.0 |
| Logo Menu | Aryan20/Logomenu | GPL-2.0 |
| User Themes | GNOME/gnome-shell-extensions | GPL-2.0-or-later |
| Display Brightness DDCUtil | daitj/gnome-display-brightness-ddcutil | GPL-3.0 |
| AppIndicator and KStatusNotifierItem Support | ubuntu/gnome-shell-extension-appindicator | GPL-2.0 |
| grub-btrfs | Antynea/grub-btrfs | GPL-3.0 |
| rEFInd (paquete de Fedora) | Roderick W. Smith | GPL-3.0 (y otras, ver el paquete) |
| rEFInd-minimal | EvanPurkhiser/rEFInd-minimal | MIT |
| rEFInd-lite | Littlebanbrick/rEFInd-lite (© 2025 Chuanyu Wang) | MIT |
| darkmini (iconos de rEFInd-lite) | LightAir/darkmini (© 2019 LightAir) | MIT |
| Waywallen y waywallen-display (opcional) | waywallen/waywallen, waywallen/waywallen-display | MIT |
| open-wallpaper-engine (opcional) | waywallen/open-wallpaper-engine | GPL-2.0 |

## Parches (`config/visual/patches/`)

Cada parche modifica una extensión de la tabla anterior y **se distribuye bajo la licencia de esa extensión**:
Dash to Dock y Logo Menu (GPL-2.0), Blur my Shell y Display Brightness DDCUtil (GPL-3.0). Los cambios están
comentados dentro de cada parche (fallos corregidos y ajustes de esta configuración).

## Fondos

Ningún fondo se incluye en el repositorio.
- **Series of Tubes** (claro y oscuro), del paquete `gnome-backgrounds` de Fedora, se copia desde el sistema al
  instalar: GNOME Design Team, **CC BY-SA 3.0**.
- **Glass Curtains** (Fedora Design, Helena Bartošová), **CC BY 4.0**: si se usa, citar autora, licencia y enlace.
- Los fondos de Wallpaper Engine (Steam Workshop) pertenecen a sus autores; el instalador solo los lee del Steam
  del usuario si este lo activa (`--wallpaper-engine`). Wallpaper Engine es una marca de sus propietarios.

macOS es una marca de Apple Inc.; este proyecto no está afiliado a Apple. Los logotipos de sistemas operativos de
los temas de rEFInd son marcas de sus propietarios.
