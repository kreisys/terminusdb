{
  description = "A very basic flake";

  inputs = {
    utils.url = "github:kreisys/flake-utils";
    terminus_store_prolog.url = "github:kreisys/terminus_store_prolog";
    tus.url = "github:kreisys/tus";
  };

  outputs = { self, nixpkgs, utils, terminus_store_prolog, tus }: utils.lib.simpleFlake {
    inherit nixpkgs;
    systems = [ "x86_64-linux" "x86_64-darwin"];

    preOverlays = [ terminus_store_prolog tus ];

    overlay = final: prev: {
      terminusdb = with final; stdenv.mkDerivation {
          pname = "terminusdb";
          version = self.shortRev or "DIRTY";
          src = self;
          buildInputs = [ swiProlog ];

          TERMINUSDB_SERVER_PACK_DIR = let
            terminusdb-swipl-packs = symlinkJoin {
              name = "terminusdb-swipl-packs";
              paths = builtins.attrValues swiplPacks;
            };
          in "${terminusdb-swipl-packs}/share/swi-prolog/pack";

          preBuild = ''
            mkdir -p $out/{bin,share/terminusdb}
            cp -r . $_
            cd $_
          '';
          installPhase = ''
            mv terminusdb $out/bin 
          '';
          dontStrip = true;

          meta = {
            mainProgram = "terminusdb";
            license = lib.licenses.asl20;
          };
        };
    };

    packages = { terminusdb }: {
      inherit terminusdb;
      defaultPackage = terminusdb;
    };
  };
}
