{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  gitUpdater,
}:

stdenvNoCC.mkDerivation rec {
  pname = "mpv-gradual-pause";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "gui-wf";
    repo = "mpv-gradual-pause";
    rev = "v${version}";
    hash = "sha256-Kir27xNEnktOG16VzetFbRCesdklnd+NHcVtsd0iGzM=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/mpv/scripts
    mkdir -p $out/share/mpv/script-opts

    # Install the main script
    cp scripts/gradual_pause.lua $out/share/mpv/scripts/

    # Install default configuration
    cp script-opts/gradual_pause.conf $out/share/mpv/script-opts/

    runHook postInstall
  '';

  passthru = {
    scriptName = "gradual_pause.lua";
    updateScript = gitUpdater { rev-prefix = "v"; };
  };

  meta = {
    description = "MPV script that adds smooth audio fade effects when pausing/unpausing";
    longDescription = ''
      Do the immediate audio cut on pausing media bugs you?
      Frustrate no more -> I fade the audio on your music and video experience.

      I'm an MPV Script that adds a fade-in and fade-out effect
      when pausing or unpausing music/video playback.

      Features logarithmic and linear volume curves, MPRIS "integration"
      support, and robust state management for seamless operation with external
      pause controls.
    '';
    homepage = "https://github.com/gui-wf/mpv-gradual-pause";
    changelog = "https://github.com/gui-wf/mpv-gradual-pause/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ gui-wf ]; # Registred in maintainers/maintainer-list.nix
    platforms = lib.platforms.all;
  };
}
