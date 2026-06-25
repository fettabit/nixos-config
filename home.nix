{ config, pkgs, inputs, ... }:

{
	imports = [
		inputs.spicetify-nix.homeManagerModules.default
	];
	home.username = "jftx";
	home.homeDirectory = "/home/jftx";
	home.stateVersion = "26.05";
	home.packages = with pkgs; [
		neovim
		vscode
		zotero
		firefox
		vesktop
		inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
	];
	programs.spicetify = 
		let
			spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
		in
		{
			enable = true;
		};
	home.sessionVariables.NIXOS_OZONE_WL = "1";
	programs.bash = {
		enable = true;
		shellAliases = {
			jftx = "echo i use nixos with hyprland btw";
            rebuild = "sudo nixos-rebuild switch --flake ~/nixos#blackgarden";
		};
		profileExtra = ''
			if uwsm check may-start && [ "$XDG_VTNR" = 1 ]; then
			    exec uwsm start hyprland-uwsm.desktop
			fi
		'';
	};


}
