# Configuration that will be added to both the nixinatee node and the nixinator
# node.
{ inputs }: {
  nix = {
    extraOptions = ''
        experimental-features = nix-command flakes
        flake-registry = ${builtins.toFile "empty-flake-registry.json" ''{"flakes":[],"version":2}''}
      '';
    registry.nixpkgs.flake = inputs.nixpkgs;
  };
}
