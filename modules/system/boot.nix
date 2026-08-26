{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [inputs.lanzaboote.nixosModules.lanzaboote];

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.efi.canTouchEfiVariables = true;
  # lanzaboote signs and installs its own systemd-boot + kernel stubs (lzbt)
  # at activation time; the module requires stock sd-boot forced off. GRUB is
  # gone entirely: no Microsoft-signed shim exists for NixOS, so GRUB cannot
  # sit in a Secure Boot chain without hand-signing every generation.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 5;
  };

  environment.systemPackages = [
    pkgs.sbctl
    pkgs.efibootmgr
    # One command to land in Windows: firmware BootNext -> Windows Boot
    # Manager (its own ESP on nvme0n1 — sd-boot cannot list it), then reboot.
    (pkgs.writeShellApplication {
      name = "boot-windows";
      runtimeInputs = [pkgs.efibootmgr];
      text = ''
        if [ "$(id -u)" -ne 0 ]; then
          exec sudo "$0" "$@"
        fi
        entry=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} *Windows Boot Manager.*/\1/p' | head -n1)
        if [ -z "$entry" ]; then
          echo "boot-windows: no 'Windows Boot Manager' entry in firmware NVRAM" >&2
          exit 1
        fi
        efibootmgr --bootnext "$entry" >/dev/null
        reboot
      '';
    })
  ];
}
