{ pkgs, lib, makeTest, inputs }: {
  vmTestLocal = (import ./vmTest { inherit pkgs lib makeTest inputs; }).local;
  vmTestRemote = (import ./vmTest { inherit pkgs lib makeTest inputs; }).remote;
  vmTestLocalHermetic = (import ./vmTest { inherit pkgs lib makeTest inputs; }).localHermetic;
  vmTestRemoteHermetic = (import ./vmTest { inherit pkgs lib makeTest inputs; }).remoteHermetic;
}
