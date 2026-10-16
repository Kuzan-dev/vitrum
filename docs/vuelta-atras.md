# Vuelta atrás y rescate

## Por capa
- **user**: `./install.sh rollback user [copia]` restaura la copia previa (archivos del HOME gestionados y ramas
  de dconf). Waywallen: `scripts/rollback-waywallen.sh` (desinstala el Flatpak y restaura sus copias).
- **system, nvidia, gaming, login**: `./install.sh rollback <capa>` hace `snapper undochange` desde el snapshot
  «pre-capa-<capa>» (muestra antes cuántos archivos cambian; /home no se toca). La primera capa system, sin
  Snapper previo: arrancar el snapshot de seguridad `root-pre-fase1` o uno del submenú «Fedora snapshots» de GRUB.
- **boot**: `sudo scripts/system/08-refind.sh theme-rollback` (vuelve a `refind.old`) o `rollback` (quita rEFInd
  y su entrada del firmware); la copia de la ESP queda en `backups/`.

## Si el escritorio no arranca (TTY)
1. En la pantalla de acceso o con la sesión colgada: **Ctrl+Alt+F3** y entrar con tu usuario.
2. Extensiones fuera: `dbus-run-session -- gsettings set org.gnome.shell disable-user-extensions true`.
3. `./install.sh rollback user --yes` (o la copia concreta) y volver a permitir las extensiones con `false`.
4. Ctrl+Alt+F1/F2 para volver a la pantalla gráfica.

## Si no arranca el sistema
- Menú de arranque del firmware (tecla según la placa: F8, F11, F12…) → la entrada «Fedora» (respaldo de rEFInd).
- Desde GRUB, el submenú «Fedora snapshots» arranca un snapshot; luego `snapper rollback` o `undochange`.
- USB live de Fedora: montar la ESP (`lsblk -o +PARTUUID`), poner Fedora primero con `efibootmgr --bootorder`,
  o restaurar en el mismo disco la copia de la ESP de `backups/` (nunca en un disco distinto: los PARTUUID cambian).
