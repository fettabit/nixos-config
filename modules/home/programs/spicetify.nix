{ inputs, pkgs, ... }:
{
    imports = [
        inputs.spicetify-nix.homeManagerModules.default
    ];

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
}