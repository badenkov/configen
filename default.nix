{
  lib,
  makeWrapper,
  ruby_3_4,
  bundlerEnv,
  stdenv,
}: let
  gems = bundlerEnv {
    name = "configen-env";
    ruby = ruby_3_4;
    gemdir = ./.;
    group = ["default"];
  };
in
  stdenv.mkDerivation {
    pname = "configen";
    version = "0.1.0";
    src = ./.;

    nativeBuildInputs = [makeWrapper];
    buildInputs = [gems gems.wrappedRuby];

    installPhase = ''
      mkdir -p $out/{bin,share/configen}
      cp -r . $out/share/configen
      chmod +x $out/share/configen/bin/configen

      makeWrapper $out/share/configen/bin/configen $out/bin/configen
    '';
  }
