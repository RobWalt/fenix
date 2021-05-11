{
  description = "Rust nightly toolchains and rust analyzer nightly for nix";

  inputs = {
    naersk = {
      url = "github:nmattia/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-analyzer-src = {
      url = "github:rust-analyzer/rust-analyzer/nightly";
      flake = false;
    };
  };

  outputs = { self, naersk, nixpkgs, rust-analyzer-src }: rec {
    defaultPackage = packages;

    packages = with builtins;
      mapAttrs (k: v:
        let
          pkgs = nixpkgs.legacyPackages.${k};
          mkToolchain = pkgs.callPackage ./lib/mk-toolchain.nix { };
          nightly = mapAttrs (_:
            mapAttrs (profile:
              { date, components }:
              mkToolchain "rust-nightly-${profile}" date components))
            (fromJSON (readFile ./data/nightly.json));
          rust-analyzer-rev = substring 0 7 (fromJSON
            (readFile ./flake.lock)).nodes.rust-analyzer-src.locked.rev;
        in nightly.${v} // rec {
          combine = pkgs.callPackage ./lib/combine.nix { } "rust-nightly-mixed";

          targets = nightly;

          rust-analyzer = (naersk.lib.${k}.override {
            inherit (nightly.${v}.minimal) cargo rustc;
          }).buildPackage {
            name = "rust-analyzer-nightly";
            version = rust-analyzer-rev;
            src = rust-analyzer-src;
            cargoBuildOptions = xs: xs ++ [ "-p" "rust-analyzer" ];
            CARGO_INCREMENTAL = "0";
            RUST_ANALYZER_REV = rust-analyzer-rev;
          };

          rust-analyzer-vscode-extension = let
            setDefault = k: v: ''
              .contributes.configuration.properties."rust-analyzer.${k}".default = "${v}"
            '';
          in pkgs.vscode-utils.buildVscodeExtension {
            name = "rust-analyzer-${rust-analyzer-rev}";
            src = ./data/rust-analyzer-vsix.zip;
            vscodeExtUniqueId = "matklad.rust-analyzer";
            buildInputs = with pkgs; [ jq moreutils ];
            patchPhase = ''
              jq -e '
                ${setDefault "server.path" "${rust-analyzer}/bin/rust-analyzer"}
                | ${setDefault "updates.channel" "nightly"}
              ' package.json | sponge package.json
            '';
          };
        }) {
          aarch64-linux = "aarch64-unknown-linux-gnu";
          i686-linux = "i686-unknown-linux-gnu";
          x86_64-darwin = "x86_64-apple-darwin";
          x86_64-linux = "x86_64-unknown-linux-gnu";
        };

    overlay = import ./lib/overlay.nix (pkgs: packages.${pkgs.system});
  };
}
