{ pkgs, lib, craneLib }: rec {
  mkDirect = drv:
    pkgs.runCommand drv.pname { } ''
      cp ${drv}/bin/${drv.pname} $out
    '';

  crate = path:
    let
      src = craneLib.cleanCargoSource path;
      metadata = craneLib.crateNameFromCargoToml { inherit src; };
    in {
      inherit src;
      name = metadata.pname;
    };

  joinSpace = lst: builtins.concatStringsSep " " lst;

  filterArgs = { extra ? [ ] }:
    args:
    let
      defaultFilters = [ "defaultFeatures" "features" ];
      filters = defaultFilters ++ extra;
    in builtins.removeAttrs args filters;

  cargoArgs = { defaultFeatures, features, extra ? "" }:
    let
      noDefaultFeaturesArg =
        if !defaultFeatures then [ "--no-default-features" ] else [ ];
      extraFeaturesArg = if (builtins.length features) != 0 then
        [ "--features ${joinSpace features}" ]
      else
        [ ];
    in "${joinSpace (noDefaultFeaturesArg ++ extraFeaturesArg ++ [ extra ])}";

  defaultCraneArgs = {
    doCheck = false;
    strictDeps = true;
  };

  merge = lib.mergeAttrsList;

  concat = builtins.concatStringsSep;
}
