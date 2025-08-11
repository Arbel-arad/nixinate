{ pkgs, lib, flake, machine, dryRun }: let

  nix = pkgs.writeShellScriptBin "nix" ''${pkgs.nixVersions.latest}/bin/nix --experimental-features "nix-command flakes" "$@"'' // { inherit (pkgs.nixVersions.latest) version; };
  nixos-rebuild = lib.getExe (pkgs.nixos-rebuild-ng.override { inherit nix; });
  openssh = "${pkgs.openssh}/bin/ssh";
  flock = "${pkgs.flock}/bin/flock";
  n = flake.nixosConfigurations.${machine}._module.args.nixinate;
  hermetic = n.hermetic or true;
  user = n.sshUser or "root";
  inherit (n) host;
  where = n.buildOn or "remote";
  remote = if where == "remote" then true else if where == "local" then false else builtins.abort "_module.args.nixinate.buildOn is not set to a valid value of 'local' or 'remote'";
  substituteOnTarget = n.substituteOnTarget or false;
  switch = if dryRun then "dry-activate" else "switch";
  nixOptions = lib.concatStringsSep " " (n.nixOptions or []);
  flakeArgs = n.flakeArgs or "";
  flakePath = n.flakePath or flake;

in pkgs.writeShellScriptBin "deploy-${machine}.sh"
  (''
    set -e
    printf "🚀 Deploying nixosConfigurations.${machine} from ${flake}\n👤 SSH User: ${user}\n🌐 SSH Host: ${host}\n"
  '' + (if remote then ''
    echo "🚀 Sending flake to ${machine} via nix copy:"
    ( set -x; ${nix} ${nixOptions} copy ${flake} --to ssh://${user}@${host} )
  '' + (if hermetic then ''
    echo "🤞 Activating configuration hermetically on ${machine} via ssh:"
    ( set -x; ${nix} ${nixOptions} copy --derivation ${nixos-rebuild} ${flock} --to ssh://${user}@${host} )
    ( set -x; ${openssh} $NIX_SSHOPTS -t ${user}@${host} "sudo nix-store --realise ${nixos-rebuild} ${flock} && sudo ${flock} -w 60 /dev/shm/nixinate-${machine} ${nixos-rebuild} ${nixOptions} ${switch} --flake ${flakePath}#${machine}${flakeArgs}" )
  '' else ''
    echo "🤞 Activating configuration non-hermetically on ${machine} via ssh:"
    ( set -x; ${openssh} $NIX_SSHOPTS -t ${user}@${host} "sudo flock -w 60 /dev/shm/nixinate-${machine} nixos-rebuild ${switch} --flake ${flakePath}#${machine}${flakeArgs}" )
  '')
  else ''
    echo "🔨 Building system closure locally, copying it to remote store and activating it:"
    ( set -x; NIX_SSHOPTS="-t" ${flock} -w 60 /dev/shm/nixinate-${machine} ${nixos-rebuild} ${nixOptions} ${switch} --flake ${flakePath}#${machine}${flakeArgs} --target-host ${user}@${host} --sudo --no-reexec ${lib.optionalString substituteOnTarget "-s"} )

  ''))


