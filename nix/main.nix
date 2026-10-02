{ system, nixpkgs, rust-overlay, crane, ... }:
let
  pkgs = nixpkgs.legacyPackages.${system}.extend (import rust-overlay);
  rustToolchain = pkgs: pkgs.rust-bin.stable.latest.default;
  craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

  util = import ./util.nix {
    inherit pkgs craneLib;
    lib = pkgs.lib;
  };
  brimstone = lib.direct.build { src = ../.; };

  lib = {
    # Straightforward Crane build helper
    build = args@{ src, defaultFeatures ? true, features ? [ ], ... }:
      let
        commonArgs = util.merge [
          util.defaultCraneArgs
          (util.filterArgs { } args)
          {
            src = craneLib.cleanCargoSource src;
            cargoExtraArgs =
              util.cargoArgs { inherit defaultFeatures features; };
          }
        ];
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
      in craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

    # Build a single crate in a workspace (this is not using the clever
    # fileset stuff from the crane docs so the input hash will depend on
    # everything in the workspace)
    buildFromWorkspace =
      args@{ src, crate, defaultFeatures ? true, features ? [ ], ... }:
      let
        commonArgs = util.merge [
          util.defaultCraneArgs
          (util.filterArgs { extra = [ "crate" ]; } args)
          {
            inherit (metadata) pname version;
            src = craneLib.cleanCargoSource src;
            cargoExtraArgs =
              util.cargoArgs { inherit defaultFeatures features; };
          }
        ];
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        metadata = craneLib.crateNameFromCargoToml { src = "${src}/${crate}"; };
      in craneLib.buildPackage (commonArgs // {
        inherit cargoArtifacts;
        cargoExtraArgs = util.cargoArgs {
          inherit defaultFeatures features;
          extra = "-p ${metadata.pname}";
        };
      });

    # Build a project which depends on path dependencies. The path
    # dependencies should be added to the flake as non-flake inputs. This
    # function creates a virtual workspace to consume the provided
    # dependencies correctly so the original project cannot be a workspace.
    # Also the assumption here is the out of tree path dependencies are comsumed
    # like `../dep`
    buildWithPathDependencies = args@{ src, pathDependencies
      , defaultFeatures ? true, features ? [ ], ... }:
      let
        metadata = craneLib.crateNameFromCargoToml { inherit src; };
        crates = [ (util.crate src) ]
          ++ builtins.map util.crate pathDependencies;

        copyCommands =
          builtins.map (dep: "cp -a ${dep.src}/. $out/crates/${dep.name}")
          crates;

        cargoLocks =
          util.joinSpace (builtins.map (d: "${d.src}/Cargo.lock") crates);
        cargoLockCommand = "${brimstone} ${cargoLocks} --out $out/Cargo.lock";

        workspace = pkgs.runCommand metadata.pname { } (util.concat "\n"
          ([ "mkdir -p $out/crates/" ] ++ copyCommands ++ [
            cargoLockCommand
            ''
              cat > $out/Cargo.toml <<'EOF'
              [workspace]
              resolver = "3"
              members = ["crates/*"]
              EOF
            ''
          ]));

      in lib.buildFromWorkspace (util.merge [
        (util.filterArgs { extra = [ "pathDependencies" ]; } args)
        {
          inherit defaultFeatures features;
          src = workspace;
          crate = "crates/${metadata.pname}";
        }
      ]);

    # Versions of all the top level functions which produce the binary
    # directly instead of in a bin directory
    direct = {
      build = args: let base = lib.build args; in util.mkDirect base;
      buildFromWorkspace = args:
        let base = lib.buildFromWorkspace args;
        in util.mkDirect base;
      buildWithPathDependencies = args:
        let base = lib.buildWithPathDependencies args;
        in util.mkDirect base;
    };
  };

in lib
