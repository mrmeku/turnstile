{
  description = "Turnstile: the toolchain, the test cluster's Postgres, and the two policy engines";

  # Pins verified on 2026-09-08 against nixos-unstable at commit dc5d91f8:
  #   pkgs/development/interpreters/erlang/29.nix          -> OTP 29.0.6
  #   pkgs/development/interpreters/elixir/1.20.nix        -> Elixir 1.20.4
  #   pkgs/servers/sql/postgresql/18.nix                   -> PostgreSQL 18.6
  #   pkgs/by-name/op/openfga/package.nix                  -> OpenFGA 1.19.0
  # Cerbos has no nixpkgs package; the release tarball is fetched below.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      imports = [ inputs.process-compose-flake.flakeModule ];

      perSystem =
        { pkgs, system, ... }:
        let
          beam = pkgs.beam.packages.erlang_29;
          elixir = beam.elixir_1_20;
          postgresql = pkgs.postgresql_18;
          openfga = pkgs.openfga;

          # Cerbos 0.55.0, the latest release at https://api.github.com/repos/cerbos/cerbos/releases/latest
          # on 2026-09-08 (published 2026-08-13). Hashes computed from the downloaded assets
          # with `openssl dgst -sha256 -binary | base64`.
          # Gatekeeper on macOS: the binary comes from a tarball, not a notarised app bundle,
          # so no quarantine attribute is attached and it runs without a prompt. Recorded at S0.
          cerbos =
            let
              version = "0.55.0";
              assets = {
                aarch64-darwin = {
                  suffix = "Darwin_arm64";
                  hash = "sha256-6kgNpjnKfJOtF4/MGSQJITPwh0MR/za2fUVwZJV9G3Q=";
                };
                x86_64-darwin = {
                  suffix = "Darwin_x86_64";
                  hash = "sha256-+tkmxBrBlwFgrJ7DAFFEmRlanary+d6xjOuX18+3III=";
                };
                aarch64-linux = {
                  suffix = "Linux_arm64";
                  hash = "sha256-g4ydEzmmngePzLHzDlv9hWYsOzttQqFCwza7NNHl46M=";
                };
                x86_64-linux = {
                  suffix = "Linux_x86_64";
                  hash = "sha256-Acta4LiIOTIZhGwbxD1O0aRwGlH7iuOFI9OjeOaF78o=";
                };
              };
              asset = assets.${system} or (throw "cerbos ${version}: no release asset for ${system}");
            in
            pkgs.stdenvNoCC.mkDerivation {
              pname = "cerbos";
              inherit version;
              src = pkgs.fetchurl {
                url = "https://github.com/cerbos/cerbos/releases/download/v${version}/cerbos_${version}_${asset.suffix}.tar.gz";
                inherit (asset) hash;
              };
              sourceRoot = ".";
              dontBuild = true;
              installPhase = ''
                mkdir -p $out/bin
                install -m755 cerbos cerbosctl $out/bin/
              '';
              meta = {
                description = "Cerbos policy decision point";
                homepage = "https://cerbos.dev";
                license = pkgs.lib.licenses.asl20;
                mainProgram = "cerbos";
              };
            };

          tools = [
            beam.erlang
            elixir
            postgresql
            openfga
            cerbos
          ];
        in
        {
          packages = {
            inherit cerbos openfga postgresql elixir;
            default = elixir;
          };

          devShells.default = pkgs.mkShell {
            packages = tools ++ [ pkgs.git ];
            # Hex and rebar live inside the checkout so the shell owns its own state.
            shellHook = ''
              export LANG=C.UTF-8
              root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              export MIX_HOME="$root/.nix-mix"
              export HEX_HOME="$root/.nix-hex"
              export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"
              export ERL_AFLAGS="-kernel shell_history enabled"
              mix local.hex --force --if-missing >/dev/null
              mix local.rebar --force --if-missing >/dev/null
            '';
          };

          # `nix run .#services`: a development Postgres and both engines for
          # manual exploration. The test suite never uses these; it starts its own cluster.
          process-compose."services" = {
            imports = [ inputs.services-flake.processComposeModules.default ];
            services.postgres."postgres" = {
              enable = true;
              package = postgresql;
              listen_addresses = "127.0.0.1";
              port = 5432;
              dataDir = "./tmp/services/postgres";
              socketDir = "./tmp/services/postgres-socket";
              initialScript.before = ''
                CREATE ROLE turnstile_owner LOGIN;
                CREATE ROLE turnstile_app LOGIN NOBYPASSRLS;
              '';
              initialDatabases = [ { name = "turnstile_dev"; } ];
            };
            settings.processes = {
              cerbos.command = ''
                mkdir -p "$PWD/tmp/services/cerbos-policies"
                exec ${cerbos}/bin/cerbos server \
                  --set=server.httpListenAddr=127.0.0.1:3592 \
                  --set=server.grpcListenAddr=127.0.0.1:3593 \
                  --set=storage.driver=disk \
                  --set=storage.disk.directory="$PWD/tmp/services/cerbos-policies" \
                  --set=storage.disk.watchForChanges=true
              '';
              openfga.command = ''
                exec ${openfga}/bin/openfga run \
                  --datastore-engine memory \
                  --http-addr 127.0.0.1:8080 \
                  --grpc-addr 127.0.0.1:8081 \
                  --playground-enabled=false
              '';
            };
          };
        };
    };
}
