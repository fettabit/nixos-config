{ ... }:
{
    programs.bash = {
		enable = true;
		shellAliases = {
			jftx = "echo i use nixos with hyprland btw";
            rb = "nixos-rebuild switch --flake ~/nixos#blackgarden --sudo";
			nixcfg = "cd ~/nixos && code .";
			hyprcfg = "cd ~/.config/hypr && code .";
		};
		profileExtra = ''
			if uwsm check may-start && [ "$XDG_VTNR" = 1 ]; then
			    exec uwsm start hyprland-uwsm.desktop
			fi
		'';
	};
}