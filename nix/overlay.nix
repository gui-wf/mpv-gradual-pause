final: prev: {
  mpvScripts = prev.mpvScripts or { } // {
    gradual-pause = final.callPackage ./package.nix { };
  };
}
