{ isDevelopment ? true }:

let
  # Update packages with `nixpkgs-update` command
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/6c25325ec30a566f5c0446ceee61ada081903872.tar.gz") { };

  pythonLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib.out
  ];

  # Override LD_LIBRARY_PATH to load Python libraries
  wrappedPython = with pkgs; (symlinkJoin {
    name = "python";
    paths = [
      # Enable compiler optimizations when in production
      (if isDevelopment then python312 else python312.override { enableOptimizations = true; })
    ];
    buildInputs = [ makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/python3.12" --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath pythonLibs}"
    '';
  });

  packages' = with pkgs; [
    wrappedPython
    poetry
    ruff
    biome
    gcc
    esbuild

    # Scripts
    # -- Cython
    (writeShellScriptBin "cython-build" ''
      python setup.py build_ext --build-lib cython_lib
    '')
    (writeShellScriptBin "cython-clean" ''
      rm -rf build/ cython_lib/*{.c,.html,.so}
    '')
    # -- Misc
    (writeShellScriptBin "make-version" ''
      sed -i -r "s|VERSION = '([0-9.]+)'|VERSION = '\1.$(date +%y%m%d)'|g" config.py
    '')
    (writeShellScriptBin "make-bundle" ''
      chmod +w static/js static/css templates

      # menu.js
      HASH=$(esbuild static/js/menu.js --bundle --minify | sha256sum | head -c8 ; echo "") && \
      esbuild static/js/menu.js --bundle --minify --sourcemap --charset=utf8 --outfile=static/js/menu.$HASH.js && \
      find templates -type f -exec sed -i 's|src="/static/js/menu.js" type="module"|src="/static/js/menu.'$HASH'.js"|g' {} \;

      # style.css
      HASH=$(esbuild static/css/style.css --bundle --minify | sha256sum | head -c8 ; echo "") && \
      esbuild static/css/style.css --bundle --minify --sourcemap --charset=utf8 --outfile=static/css/style.$HASH.css && \
      find templates -type f -exec sed -i 's|href="/static/css/style.css"|href="/static/css/style.'$HASH'.css"|g' {} \;
    '')
    (writeShellScriptBin "nixpkgs-update" ''
      set -e
      hash=$(git ls-remote https://github.com/NixOS/nixpkgs nixpkgs-unstable | cut -f 1)
      sed -i -E "s|/nixpkgs/archive/[0-9a-f]{40}\.tar\.gz|/nixpkgs/archive/$hash.tar.gz|" shell.nix
      echo "Nixpkgs updated to $hash"
    '')
    (writeShellScriptBin "docker-build-push" ''
      set -e
      cython-clean && cython-build
      if command -v podman &> /dev/null; then docker() { podman "$@"; } fi
      docker push $(docker load < $(nix-build --no-out-link) | sed -En 's/Loaded image: (\S+)/\1/p')
    '')
  ];

  shell' = with pkgs; lib.optionalString isDevelopment ''
    current_python=$(readlink -e .venv/bin/python || echo "")
    current_python=''${current_python%/bin/*}
    [ "$current_python" != "${wrappedPython}" ] && rm -r .venv

    echo "Installing Python dependencies"
    export POETRY_VIRTUALENVS_IN_PROJECT=1
    poetry env use "${wrappedPython}/bin/python"
    poetry install --no-root --compile

    echo "Activating Python virtual environment"
    source .venv/bin/activate

    # Development environment variables
    export PYTHONNOUSERSITE=1
    export TZ=UTC
    export TEST_ENV=1
    export SECRET=development-secret

    if [ -f .env ]; then
      echo "Loading .env file"
      set -o allexport
      source .env set
      set +o allexport
    fi
  '' + lib.optionalString (!isDevelopment) ''
    make-version
    make-bundle
  '';
in
pkgs.mkShell {
  buildInputs = packages';
  shellHook = shell';
}
