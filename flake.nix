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

            dontFixup = true;

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
      nixosModules.default = forAllSystems (system:
        let
          cfg = self.services.assetsDataManager;
        in {
          options.services.assetsDataManager = {
            adaptersClient = {
              instances = nixpkgs.lib.mkOption {
                default = { };
                example = {
                  "job-1".settings = {
                    workspaceId = "123456";
                    token = "SECRETTOKEN";
                  };
                };
                description = "Job instances to configure";
                type = nixpkgs.lib.types.attrsOf (
                  nixpkgs.lib.types.submodule {
                    options = {
                      settings = nixpkgs.lib.mkOption {
                        description = "Settings for adapters client";
                        default = { };
                        type = nixpkgs.lib.types.submodule {
                          freeformType = nixpkgs.lib.settingsFormat.type;

                          options = {
                            workspaceId = nixpkgs.lib.mkOption {
                              type = nixpkgs.lib.types.singleLineStr;
                              description = "Workspace ID for the job";
                            };

                            token = nixpkgs.lib.mkOption {
                              type = nixpkgs.lib.types.singleLineStr;
                              description = "Token to authenticate against Assets Data Manager";
                            };
                          };
                        };
                      };
                    };
                  }
                );
              };
            };
            cleanseImportClient = {
              instances = nixpkgs.lib.mkOption {
                default = [ ];
                example = [
                  {
                    run = "full";
                    workspaceId = "123456";
                    token = "SECRETTOKEN";
                    object = "foo";
                    ds = "bar";
                    type = "baz";
                  }
                ];
                description = "Job instances to configure";
                type = nixpkgs.lib.types.listOf (
                  nixpkgs.lib.types.submodule {
                    options = {
                      run = nixpkgs.lib.mkOption {
                        type = nixpkgs.lib.types.enum ["full" "cleanse" "import"];
                        description = "Type of the job to run";
                      };
                      workspaceId = nixpkgs.lib.mkOption {
                        type = nixpkgs.lib.types.singleLineStr;
                        description = "Workspace ID for the job";
                      };
                      token = nixpkgs.lib.mkOption {
                        type = nixpkgs.lib.types.singleLineStr;
                        description = "Token to authenticate against Assets Data Manager";
                      };
                      object = nixpkgs.lib.mkOption {
                        type = nixpkgs.lib.types.singleLineStr;
                        description = "Object name to run import and / or cleansing processes for";
                      };
                      ds = nixpkgs.lib.mkOption {
                        type = nixpkgs.lib.types.singleLineStr;
                        description = "Data source name to run import and / or cleansing processes for";
                      };
                      type = nixpkgs.lib.mkOption {
                        type = nixpkgs.lib.types.singleLineStr;
                        description = "Data source type name to run import and / or cleansing processes for";
                      };
                    };
                  }
                );
              };
            };
          };
          config = {
            systemd.services = nixpkgs.lib.mapAttrs' (jobname: jobcfg: {
              name = "dataManagerAdaptersClient-${jobname}";
              value = {
                description = "Assets Data Manager Adapters instance for job ${jobname}";
                after = [
                  "network.target"
                ];
                wants = [ "network-online.target" ];
                serviceConfig = {
                    ExecStart = "${self.packages."${system}".default}/bin/dm-adapters --token ${jobcfg.settings.token} --workspace-id ${jobcfg.settings.workspaceId} --run ${jobname}";
                    Restart = "on-failure";
                    User = "datamanager";
                    Group = "datamanager";
                  };
              };
            }) cfg.adaptersClient.instances +
            nixpkgs.lib.mapAttrs' (jobcfg: {
              name = nixpkgs.lib.strings.concatStringsSep "-" [
                "dataManagerCleanseImportClient"
                nixpkgs.lib.strings.optionalString (jobcfg.object != null) "object_${jobcfg.object}"
                nixpkgs.lib.strings.optionalString (jobcfg.ds != null) "ds_${jobcfg.ds}"
                nixpkgs.lib.strings.optionalString (jobcfg.type != null) "type_${jobcfg.type}"
              ];
              value = {
                description = nixpkgs.lib.strings.concatStringsSep ", " [
                  "Assets Data Manager Cleanse and Import instance for job "
                  nixpkgs.lib.strings.optionalString (jobcfg.object != null) "object: ${jobcfg.object}"
                  nixpkgs.lib.strings.optionalString (jobcfg.ds != null) "ds: ${jobcfg.ds}"
                  nixpkgs.lib.strings.optionalString (jobcfg.type != null) "type: ${jobcfg.type}"
                ];
                after = [
                  "network.target"
                ];
                wants = [ "network-online.target" ];
                serviceConfig = {
                  ExecStart = nixpkgs.lib.strings.concatStringsSep " " [
                    "${self.packages."${system}".default}/bin/dm-cleanseimport --token ${jobcfg.token} --workspace-id ${jobcfg.workspaceId} --run ${jobcfg.run}"
                    nixpkgs.lib.strings.optionalString (jobcfg.object != null) "--object ${jobcfg.object}"
                    nixpkgs.lib.strings.optionalString (jobcfg.ds != null)     "--ds ${jobcfg.ds}"
                    nixpkgs.lib.strings.optionalString (jobcfg.type != null)   "--type ${jobcfg.type}"
                  ];
                  Restart = "on-failure";
                  User = "datamanager";
                  Group = "datamanager";
                };
              };
            }) cfg.cleanseImportClient.instances;
          };
        }
      );
    };
}
