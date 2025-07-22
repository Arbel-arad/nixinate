{
  description = "Nixinate your systems";
  inputs = {
    nixpkgs.url = "git+https://forgejo.spacetime.technology/nix-mirrors/nixpkgs?ref=nixpkgs-unstable&shallow=1";
    flake-parts.url = "git+https://forgejo.spacetime.technology/nix-mirrors/flake-parts?shallow=1";
    system.url = "git+https://forgejo.spacetime.technology/arbel/nix-system?shallow=1";
  };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    systems = inputs.system.wellSupportedArches;
    flake = { lib, ... }: {
      lib = let

        validMachines = flake: lib.remove "" (lib.forEach (
          builtins.attrNames flake.nixosConfigurations) (x:
            lib.optionalString (flake.nixosConfigurations."${x}"._module.args ? nixinate) "nixinate-${x}"
          )
        );

        mkDeployScript = { pkgs, machine, flake, dryRun }: import ./mkDeployScript.nix {
          inherit pkgs lib machine flake dryRun;
        };

      in {
        nixinate = { pkgs, flake }: lib.genAttrs (validMachines flake) (machine: {
          type = "app";
          program = mkDeployScript {
            inherit pkgs flake;
            machine = builtins.substring 9 (-1) "${machine}";
            dryRun = false;
          };
          meta = {
            description = "Deploy configuration on ${machine}";
          };
        });
      };
    };
    perSystem = { pkgs, lib, system, ... }: {
      checks = lib.optionalAttrs pkgs.stdenv.isLinux (import ./tests {
        inherit (import (inputs.nixpkgs + "/nixos/lib/testing-python.nix") { inherit system; }) makeTest;
        inherit inputs pkgs lib;
      });
    };
  };
}
