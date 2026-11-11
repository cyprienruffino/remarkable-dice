{
  inputs.remarkable-sdk.url = "github:cyprienruffino/nix-remarkable-sdk";

  outputs = { remarkable-sdk, ... }: {
    devShells = remarkable-sdk.devShells;
  };
}
