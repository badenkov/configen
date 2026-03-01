{
  description = "Fast configuration file manager with ERB templating and theme support";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = self.packages.${system}.configen;
      configen = pkgs.callPackage ./default.nix {};
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      ruby = pkgs.ruby_3_4;
      bundler = pkgs.bundler.override {inherit ruby;};
    in {
      default = pkgs.mkShell {
        packages = [
          ruby
          bundler
          pkgs.bundix
          pkgs.libyaml
        ];

        shellHook = ''
          export GEM_HOME="$PWD/.devstate/bundle"
          export BUNDLE_PATH="$GEM_HOME"
          export RUBOCOP_CACHE_ROOT="$PWD/.devstate/rubocop_cache"
          export PATH="$PWD/bin:$BUNDLE_PATH/bin:$PATH"
        '';
      };
    });

    nixosModules.default = self.nixosModules.configen;
    nixosModules.configen = {pkgs, ...}: {
      imports = [./module.nix];

      config.configen.package = nixpkgs.lib.mkDefault self.packages.${pkgs.system}.configen;
    };
  };
}
