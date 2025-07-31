# Nixinate 🕶️

Nixinate is a proof of concept that generates a deployment script for each
`nixosConfiguration` you already have in your flake, which can be ran via `nix
run`, thanks to the `apps` attribute of the [flake
schema](https://wiki.nixos.org/wiki/Flakes#Flake_schema).

## Usage

To use `nixinate` in your own flake, you need to:

1. Add the result of `nixinate.lib.nixinate {}` to the `apps` attribute of your flake.
2. Configure `_module.args.nixinate` for the `nixosConfigurations` you want to deploy

Below is a minimal example:

```nix
{
  inputs = {
    nixpkgs.url = "git+https://forgejo.spacetime.technology/nix-mirrors/nixpkgs?ref=nixpkgs-unstable&shallow=1";
    flake-parts.url = "git+https://forgejo.spacetime.technology/nix-mirrors/flake-parts?shallow=1";
    nixinate = {
      url = "git+https://forgejo.spacetime.technology/arbel/nixinate?shallow=1";
      inputs = {
        flake-parts.follows = "flake-parts";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, ... }@inputs:
  inputs.flake-parts.lib.mkFlake { inherit inputs self; } {
    systems = [ "x86_64-linux" ];
    perSystem = { pkgs, ... }: {
      apps = { /* other apps */ } // inputs.nixinate.lib.nixinate { inherit pkgs; flake = self; };
    };
    flake = {
      nixosConfigurations = {
        myMachine = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            {
              _module.args.nixinate = {
                host = "itchy.scratchy.com";
                sshUser = "matthew";
                buildOn = "remote"; # valid args are "local" or "remote"
                substituteOnTarget = true; # if buildOn is "local", substitute on target
                hermetic = false;
              };
            }
            # ... other configuration ...
          ];
        };
      };
    };
  };
}
```

Each `nixosConfiguration` you have configured should have a deployment script in
`apps.${system}`, visible in `nix flake show` like this:

``` bash
$ nix flake show
git+file:///etc/nixos
├───apps
│   └───x86_64-linux
│        └───nixinate-myMachine: app: Deploy configuration on nixinate-myMachine
└───nixosConfigurations
    └───myMachine: NixOS configuration
```

To finally execute the deployment script, use `nix run .#apps.nixinate-myMachine`

### Example Run

``` bash
[root@myMachine:/etc/nixos]# nix run .#apps.nixinate-myMachine
🚀 Deploying nixosConfigurations.myMachine from /nix/store/279p8aaclmng8kc3mdmrmi6q3n76r1i7-source
👤 SSH User: matthew
🌐 SSH Host: itchy.scratchy.com
🚀 Sending flake to myMachine via nix copy:
(matthew@itchy.scratchy.com) Password:
🤞 Activating configuration on myMachine via ssh:
(matthew@itchy.scratchy.com) Password:
[sudo] password for matthew:
building the system configuration...
activating the configuration...
setting up /etc...
reloading user units for matthew...
setting up tmpfiles
Connection to itchy.scratchy.com closed.
```

## Available arguments via `_module.args.nixinate`

- `host` *`string`*

   A string representing the hostname or IP address of a machine to connect to
   via ssh.

- `sshUser` *`string`*

   A string representing the username a machine to connect to via ssh.

- `buildOn` *`"remote"`* or *`"local"`*

  - `"remote"`

    Push the flake to the remote, build and activate entirely remotely,
    returning logs via SSH.

  - `"local"`

    Build the system closure locally, copy to the remote and activate.

- `hermetic` *`bool`*

  Whether to copy Nix to the remote for usage when building and activating,
  instead of using the Nix which is already installed on the remote.

- `substituteOnTarget` *`bool`*

  Whether to fetch closures and paths from the remote, even when building
  locally. This makes sense in most cases, because the remote will have already
  built a lot of the paths from the previous deployment. However, if the remote
  has a slow upload bandwidth, this would not be a good idea to enable.
