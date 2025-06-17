{
  description = "Nixinate your systems";
  inputs = {
    nixpkgs.url = "git+https://forgejo.spacetime.technology/nix-mirrors/nixpkgs?ref=nixpkgs-unstable&shallow=1";
    system.url = "git+https://forgejo.spacetime.technology/arbel/nix-system?shallow=1";
  };
  outputs = inputs: let
      forAllSystems = f:
        inputs.nixpkgs.lib.genAttrs inputs.system.arches (system: f system inputs.nixpkgs.legacyPackages.${system});
      nixpkgsFor = forAllSystems (system: pkgs: import inputs.nixpkgs { inherit system; overlays = [ inputs.self.overlay ]; });
  in {
    herculesCI.ciSystems = [ "x86_64-linux" ];
    overlay = final: prev: {
      nixinate = {
        nix = prev.pkgs.writeShellScriptBin "nix" ''${final.nixVersions.unstable}/bin/nix --experimental-features "nix-command flakes" "$@"'';
        nixos-rebuild = prev.nixos-rebuild.override { inherit (final) nix; };
      };
      generateApps = flake: let
          machines = builtins.attrNames flake.nixosConfigurations;
          validMachines = final.lib.remove "" (final.lib.forEach machines (x: final.lib.optionalString (flake.nixosConfigurations."${x}"._module.args ? nixinate) "${x}" ));
          mkDeployScript = { machine, dryRun }: let
            inherit (builtins) abort;
            inherit (final.lib) getExe optionalString concatStringsSep;
            nix = "${getExe final.nix}";
            nixos-rebuild = "${getExe final.nixos-rebuild}";
            openssh = "${getExe final.openssh}";
            flock = "${getExe final.flock}";
            n = flake.nixosConfigurations.${machine}._module.args.nixinate;
            hermetic = n.hermetic or true;
            user = n.sshUser or "root";
            inherit (n) host;
            where = n.buildOn or "remote";
            remote = if where == "remote" then true else if where == "local" then false else abort "_module.args.nixinate.buildOn is not set to a valid value of 'local' or 'remote'";
            substituteOnTarget = n.substituteOnTarget or false;
            switch = if dryRun then "dry-activate" else "switch";
            nixOptions = concatStringsSep " " (n.nixOptions or []);
            flakeArgs = n.flakeArgs or "";
            flakePath = n.flakePath or flake;
          in final.writeShellScript "deploy-${machine}.sh"
           (''
              set -e
              printf "🚀 Deploying nixosConfigurations.${machine} from ${flake}\n👤 SSH User: ${user}\n🌐 SSH Host: ${host}\n"
            '' + (if remote then ''
              echo "🚀 Sending flake to ${machine} via nix copy:"
              ( set -x; ${nix} ${nixOptions} copy ${flake} --to ssh://${user}@${host} )
            '' + (if hermetic then ''
              echo "🤞 Activating configuration hermetically on ${machine} via ssh:"
              ( set -x; ${nix} ${nixOptions} copy --derivation ${nixos-rebuild} ${flock} --to ssh://${user}@${host} )
              ( set -x; ${openssh} $NIX_SSHOPTS -t ${user}@${host} "sudo nix-store --realise ${nixos-rebuild} ${flock} && sudo ${flock} -w 60 /dev/shm/nixinate-${machine} ${nixos-rebuild} ${nixOptions} ${switch} --flake ${flakePath}${flakeArgs}#${machine}" )
            '' else ''
              echo "🤞 Activating configuration non-hermetically on ${machine} via ssh:"
              ( set -x; ${openssh} $NIX_SSHOPTS -t ${user}@${host} "sudo flock -w 60 /dev/shm/nixinate-${machine} nixos-rebuild ${switch} --flake ${flakePath}${flakeArgs}#${machine}" )
            '')
            else ''
              echo "🔨 Building system closure locally, copying it to remote store and activating it:"
              ( set -x; NIX_SSHOPTS="-t" ${flock} -w 60 /dev/shm/nixinate-${machine} ${nixos-rebuild} ${nixOptions} ${switch} --flake ${flakePath}${flakeArgs}#${machine} --target-host ${user}@${host} --sudo --no-reexec ${optionalString substituteOnTarget "-s"} )

            ''));
        in {
          nixinate = (
            inputs.nixpkgs.lib.genAttrs validMachines (x: {
              type = "app";
              program = toString (mkDeployScript {
                machine = x;
                dryRun = false;
              });
            })
          );
        };
      };
    nixinate = forAllSystems (system: pkgs: nixpkgsFor.${system}.generateApps);
    checks = forAllSystems (system: pkgs:
      let
        vmTests = import ./tests {
          inherit (import (inputs.nixpkgs + "/nixos/lib/testing-python.nix") { inherit system; }) makeTest;
          inherit inputs; pkgs = nixpkgsFor.${system};
        };
      in
      pkgs.lib.optionalAttrs pkgs.stdenv.isLinux vmTests # vmTests can only be ran on Linux, so append them only if on Linux.
      // {
        # Other checks here...
      }
    );
  };
}
