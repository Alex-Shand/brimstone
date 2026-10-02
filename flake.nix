{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, crane }:
    let
      bySystem = flake-utils.lib.eachDefaultSystem (system:
        let
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs { inherit system overlays; };
          rustToolchain = pkgs: pkgs.rust-bin.stable.latest.default;
          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

          helpers = {
            mkDirect = drv:
              pkgs.runCommand drv.pname { } ''
                cp ${drv}/bin/${drv.pname} $out
              '';

            processPathDep = path:
              let
                src = craneLib.cleanCargoSource path;
                metadata = craneLib.crateNameFromCargoToml { inherit src; };
              in {
                inherit src;
                name = metadata.pname;
              };

            joinSpace = lst: builtins.concatStringsSep " " lst;
          };

          brimstone = lib.direct.build { src = ./.; };

          lib = {
            # Straightforward Crane build helper
            build = args@{ src, defaultFeatures ? true, features ? [ ], ... }:
              let
                removedAttrs = [ "defaultFeatures" "features" ];
                filteredArgs = builtins.removeAttrs args removedAttrs;

                noDefaultFeaturesArg =
                  if !defaultFeatures then [ "--no-default-features" ] else [ ];
                extraFeaturesArg = if (builtins.length features) != 0 then
                  [ "--features ${helpers.joinSpace features}" ]
                else
                  [ ];

                commonArgs = filteredArgs // {
                  src = craneLib.cleanCargoSource src;
                  strictDeps = true;
                  doCheck = false;
                  cargoExtraArgs = "${helpers.joinSpace
                    (noDefaultFeaturesArg ++ extraFeaturesArg)}";
                };
                cargoArtifacts = craneLib.buildDepsOnly commonArgs;
              in craneLib.buildPackage
              (commonArgs // { inherit cargoArtifacts; });

            # Build a single crate in a workspace (this is not using the clever
            # fileset stuff from the crane docs so the input hash will depend on
            # everything in the workspace)
            buildFromWorkspace =
              args@{ src, crate, defaultFeatures ? true, features ? [ ], ... }:
              let
                removedAttrs = [ "crate" ];
                filteredArgs = builtins.removeAttrs args removedAttrs;

                noDefaultFeaturesArg =
                  if !defaultFeatures then [ "--no-default-features" ] else [ ];
                extraFeaturesArg = if (builtins.length features) != 0 then
                  [ "--features ${helpers.joinSpace features}" ]
                else
                  [ ];

                commonArgs = filteredArgs // {
                  inherit (metadata) pname version;
                  src = craneLib.cleanCargoSource src;
                  strictDeps = true;
                  doCheck = false;
                  cargoExtraArgs = "${helpers.joinSpace
                    (noDefaultFeaturesArg ++ extraFeaturesArg)}";
                };
                cargoArtifacts = craneLib.buildDepsOnly commonArgs;
                metadata =
                  craneLib.crateNameFromCargoToml { src = "${src}/${crate}"; };
              in craneLib.buildPackage (commonArgs // {
                inherit cargoArtifacts;
                cargoExtraArgs = "-p ${metadata.pname} ${
                    helpers.joinSpace (noDefaultFeaturesArg ++ extraFeaturesArg)
                  }";
              });

            # Build a project which depends on path dependencies. The path
            # dependencies should be added to the flake as non-flake inputs. This
            # function creates a virtual workspace to consume the provided
            # dependencies correctly so the original project cannot be a workspace
            buildWithPathDependencies = args@{ src, pathDependencies, ... }:
              let
                removedAttrs = [ "pathDependencies" ];
                filteredArgs = builtins.removeAttrs args removedAttrs;

                metadata = craneLib.crateNameFromCargoToml { inherit src; };

                cleanedSrc = craneLib.cleanCargoSource src;
                dependencies =
                  builtins.map helpers.processPathDep pathDependencies;

                dependencyCopyCommands = builtins.map
                  (dep: "cp -a ${dep.src}/. $out/crates/${dep.name}")
                  dependencies;

                dependencyCargoLocks = builtins.concatStringsSep " "
                  (builtins.map (d: "${d.src}/Cargo.lock") dependencies);
                cargoLockCommand =
                  "${brimstone} $out/crates/${metadata.pname}/Cargo.lock ${dependencyCargoLocks} --out $out/Cargo.lock";

                workspace = pkgs.runCommand metadata.pname { }
                  (builtins.concatStringsSep "\n" ([
                    "mkdir -p $out/crates/"
                    "cp -a ${cleanedSrc}/. $out/crates/${metadata.pname}"
                  ] ++ dependencyCopyCommands ++ [
                    cargoLockCommand
                    ''
                      cat > $out/Cargo.toml <<'EOF'
                      [workspace]
                      resolver = "3"
                      members = ["crates/*"]
                      EOF
                    ''
                  ]));

              in lib.buildFromWorkspace (filteredArgs // {
                src = workspace;
                crate = "crates/${metadata.pname}";
              });

            # Versions of all the top level functions which produce the binary
            # directly instead of in a bin directory
            direct = {
              build = args: let base = lib.build args; in helpers.mkDirect base;
              buildFromWorkspace = args:
                let base = lib.buildFromWorkspace args;
                in helpers.mkDirect base;
              buildWithPathDependencies = args:
                let base = lib.buildWithPathDependencies args;
                in helpers.mkDirect base;
            };
          };

        in { inherit lib pkgs; });
    in {
      new = system: {
        lib = bySystem.lib.${system};
        pkgs = bySystem.pkgs.${system};
      };
    };
}
