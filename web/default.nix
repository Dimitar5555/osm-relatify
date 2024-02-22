{ pkgs ? import <nixpkgs> { }, ... }:

let
  shell = import ./shell.nix {
    isDevelopment = false;
  };

  python-venv = pkgs.buildEnv {
    name = "python-venv";
    paths = [
      (pkgs.runCommand "python-venv" { } ''
        mkdir -p $out/lib
        cp -r "${./.venv/lib/python3.12/site-packages}"/* $out/lib
      '')
    ];
  };
in
with pkgs; dockerTools.buildLayeredImage {
  name = "docker.monicz.dev/osm-relatify";
  tag = "latest";
  maxLayers = 10;

  contents = shell.buildInputs ++ [ python-venv ];

  extraCommands = ''
    set -e
    mkdir app && cd app
    cp "${./.}"/*.py .
    cp -r "${./.}"/cython_lib .
    cp -r "${./.}"/models .
    cp -r "${./.}"/static .
    cp -r "${./.}"/templates .
    export PATH="${lib.makeBinPath shell.buildInputs}:$PATH"
    ${shell.shellHook}
  '';

  config = {
    WorkingDir = "/app";
    Env = [
      "PYTHONPATH=${python-venv}/lib"
      "PYTHONUNBUFFERED=1"
      "PYTHONDONTWRITEBYTECODE=1"
    ];
    ExposedPorts = {
      "8000/tcp" = { };
    };
    Entrypoint = [ "python" "-m" "uvicorn" "main:app" ];
    Cmd = [ "--host" "0.0.0.0" ];
  };
}
