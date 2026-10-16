# Reinstalar desde cero

## Con este repositorio
1. Instalar Fedora Workstation 44 (UEFI, btrfs por defecto), actualizar y reiniciar. Si hay GPU NVIDIA, instalar
   el driver desde `rpmfusion-nonfree-nvidia-driver` (Software → Repositorios de terceros) y reiniciar.
2. `git clone --depth 1 --branch <versión> https://github.com/Kuzan-dev/vitrum ~/vitrum && cd ~/vitrum`
3. `./install.sh check --sugerir > config/local.env`, revisar los valores (o restaurar tu `local.env` guardado)
   y `./install.sh check`.
4. `./install.sh all` (y, si quieres, `./install.sh user --waywallen …` y `./install.sh boot`). Cerrar sesión y
   volver a entrar.

## Con un respaldo de `scripts/backup-usb.sh`
El archivo (`respaldo-config-<fecha>.tar.zst.gpg` + `.sha256`) contiene el repositorio completo como `git bundle`,
`local.env`, las notas de trabajo, dconf, listas de paquetes y Flatpaks, copias de los archivos de sistema y el tar
de la ESP. Va cifrado con `gpg --symmetric` si incluye datos personales.

1. `sha256sum -c respaldo-config-*.sha256` y `gpg -d -o respaldo.tar.zst respaldo-config-*.tar.zst.gpg`.
2. `tar --zstd -xf respaldo.tar.zst` y `sha256sum -c MANIFEST.sha256` dentro.
3. `git clone respaldo-config-*/repo/dotfiles.bundle ~/dotfiles` (clonar ya valida el bundle) y copiar
   `personal/local.env` a `~/dotfiles/config/`.
4. Seguir los pasos de arriba desde `./install.sh check`. dconf: cargar **por ramas**, no entero a ciegas.

## Por qué el tar de la ESP no se restaura en otro disco
`refind.conf` y las entradas del firmware apuntan a las particiones por **PARTUUID**; en un disco nuevo cambian y
las entradas NVRAM no existen. En un equipo nuevo: `./install.sh check --sugerir` (PARTUUID nuevos en
`local.env`) y `./install.sh boot`. El tar de la ESP solo sirve para restaurar **el mismo** disco.
