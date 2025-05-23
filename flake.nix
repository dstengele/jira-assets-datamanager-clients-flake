{
  description = "Data Manager Clients for JSM Assets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };

  outputs = {self, nixpkgs, ...}:
    let
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in rec {
          default = pkgs.stdenv.mkDerivation rec {
            name = "jsm-assets-dm-clients-${version}";
            version = "1000080";

            src = pkgs.fetchzip {
              url = "https://marketplace.atlassian.com/download/apps/1234690/version/${version}";
              extension = "zip";
              stripRoot = false;
              sha256 = "sha256-rwh+iTiMX9/47WZggprDJbNhkfHtqcsnHpPlNc4hLSY=";
            };

            sourceRoot = "./source";

            dontPatchELF = true;

            installPhase = let
              path = {
                "x86_64-linux" = "linux-x64";
                "x86_64-darwin" = "osx-x64";
                "aarch64-linux" = "linux-arm64";
                "aarch64-darwin" = "osx-arm64";
              }."${system}";
            in ''
              runHook preInstall
              install -m755 -D ${path}/assets-adapters-client/dm-adapters $out/bin/dm-adapters
              install -m755 -D ${path}/assets-cleanse-and-import-client/dm-cleanseimport $out/bin/dm-cleanseimport
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              homepage = "https://marketplace.atlassian.com/apps/1234690/data-manager-clients-for-jsm-assets";
              description = "Data Manager Clients for JSM Assets";
              platforms = platforms.linux;
            };
          };
        }
      );
      apps = forAllSystems (system:
        {
          dm-adapters = {
            type = "app";
            program = "${self.packages."${system}".default}/bin/dm-adapters";
          };
          dm-cleanseimport = {
            type = "app";
            program = "${self.packages."${system}".default}/bin/dm-cleanseimport";
          };
        }
      );
    };
}
