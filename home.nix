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
	];
	programs.kitty = {
		enable = true;
		font = {
			name = "JetBrainsMono Nerd Font";
			size = 16;
		};
		settings = {
			background_opacity = "0.85";
			cursor_shape = "beam";
			window_padding_width = 10;
			confirm_os_window_close = 0;
			scrollback_lines = 10000;
			enable_audio_bell = "no";
			tab_bar_style = "powerline";
		};
	};
	programs.spicetify = 
		let
			spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
		in
		{
			enable = true;
			enabledCustomApps = with spicePkgs.apps; [
				marketplace
			];
			enabledExtensions = with spicePkgs.extensions; [
				adblockify
				shuffle
			];
			theme = spicePkgs.themes.text;
		};
	home.sessionVariables.NIXOS_OZONE_WL = "1";
	programs.bash = {
		enable = true;
		shellAliases = {
			jftx = "echo i use nixos with hyprland btw";
            rb = "sudo nixos-rebuild switch --flake ~/nixos#blackgarden";
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
