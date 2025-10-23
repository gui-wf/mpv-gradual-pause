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
      A sophisticated MPV script that eliminates jarring audio cuts by adding
      configurable fade-in and fade-out effects when pausing or unpausing video
      playback. Features logarithmic and linear volume curves, MPRIS integration
      support, and robust state management for seamless operation with external
      pause controls.
    '';
    homepage = "https://github.com/gui-wf/mpv-gradual-pause";
    changelog = "https://github.com/gui-wf/mpv-gradual-pause/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ]; # Will be filled after maintainer registration
    platforms = lib.platforms.all;
  };
}
