{
  description = "Development tools for zotero.koplugin";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              autoconf
              automake
              bash
              ccache
              cmake
              coreutils
              curl
              diffutils
              file
              findutils
              gawk
              gettext
              git
              gnumake
              gnugrep
              gnupatch
              gnused
              gnutar
              gzip
              libtool
              (luajit.withPackages (ps: [ ps.busted ]))
              meson
              nasm
              ninja
              nodejs
              perl
              pkg-config
              python3
              sdl3
              unzip
              util-linux
              wget
              xz
              zip
            ];

            shellHook =
              if pkgs.stdenv.hostPlatform.isDarwin then
                ''
                  export DYLD_LIBRARY_PATH="${pkgs.lib.getLib pkgs.sdl3}/lib''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
                ''
              else
                ''
                  export LD_LIBRARY_PATH="${pkgs.lib.getLib pkgs.sdl3}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                '';
          };
        }
      );
    };
}
