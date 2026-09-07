# Toolchain pins for the flake, verified
*Mode: Reference. Produced 2026-09-07 by a research agent. `nix` is not installed on the development machine, so nothing here came from `nix eval`; sources are the nixpkgs Git branches fetched raw, the GitHub API, hex.pm's API, and the services-flake docs. Everything checked on 2026-09-07. Re-verify before S0 lands and say where.*

## 1. cerbos in nixpkgs

| item | version found | where | checked | note |
|---|---|---|---|---|
| `cerbos` on nixpkgs `master` / `nixos-unstable` | not present | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/ce/cerbos/package.nix (404); directory listing https://api.github.com/repos/NixOS/nixpkgs/contents/pkgs/by-name/ce has `cerbero`, `cerberus`, no `cerbos`; `gh search code cerbos --repo NixOS/nixpkgs` returns `[]` | 2026-09-07 | **cerbos is not in nixpkgs at all**, on any branch. The only nixpkgs mention of Cerbos is an issue asking for their `protoc-gen-go-hashpb` tool (https://github.com/NixOS/nixpkgs/issues/290460). |
| `cerbos` on `release-26.05` / `nixos-26.05` (stable) | not present | https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/pkgs/by-name/ce/cerbos/package.nix (404) | 2026-09-07 | same |

## 2. openfga in nixpkgs

| item | version found | where | checked | note |
|---|---|---|---|---|
| `openfga` on `master` and `nixos-unstable` | 1.19.0 (src `v1.19.0`, `buildGoModule`, maintainer jlesquembre) | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/op/openfga/package.nix | 2026-09-07 | matches the repo's current docker pin exactly; tests disabled in the derivation (need Docker) |
| `openfga` on `release-26.05` / `nixos-26.05` (stable) | 1.14.2 | https://raw.githubusercontent.com/NixOS/nixpkgs/release-26.05/pkgs/by-name/op/openfga/package.nix | 2026-09-07 | stable lags five minors behind |
| `openfga` on `release-25.11` | 1.11.1 | https://raw.githubusercontent.com/NixOS/nixpkgs/release-25.11/pkgs/by-name/op/openfga/package.nix | 2026-09-07 | |

## 3. Erlang/OTP and Elixir under `beam.packages`

| item | version found | where | checked | note |
|---|---|---|---|---|
| `erlang_29` (unstable) | **29.0.6** | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/erlang/29.nix; same on `nixos-unstable` | 2026-09-07 | exactly the `.tool-versions` pin; `beam.packages.erlang_29` exists |
| `erlang_28` (unstable) | 28.5.0.6 | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/erlang/28.nix | 2026-09-07 | **`erlang_28` is still the default** (`latestVersion = "erlang_28"` in https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/top-level/beam-packages.nix) |
| `erlang_27` (unstable) | 27.3.4.17 | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/erlang/27.nix | 2026-09-07 | `erlang_26` removed 2026-04-01 as EOL |
| `elixir_1_20` (unstable) | **1.20.4** (minimumOTPVersion 27, maximumOTPVersion 29) | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/elixir/1.20.nix | 2026-09-07 | exactly the `.tool-versions` pin; so `beam.packages.erlang_29.elixir_1_20` = OTP 29.0.6 + Elixir 1.20.4, no overlay needed |
| `elixir_1_19` / `1_18` / `1_17` (unstable) | 1.19.6 / present / present | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/beam-modules/default.nix | 2026-09-07 | plain `elixir` still defaults to `elixir_1_18`; 1.15/1.16 removed |
| `erlang_29` and `elixir_1_20` on stable `release-26.05` | 29.0.6 and 1.20.4 | https://raw.githubusercontent.com/NixOS/nixpkgs/release-26.05/pkgs/development/interpreters/erlang/29.nix and .../elixir/1.20.nix | 2026-09-07 | stable already has the same patch versions (backported) |

## 4. PostgreSQL majors

| item | version found | where | checked | note |
|---|---|---|---|---|
| `postgresql_17` (unstable) | 17.11 | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/servers/sql/postgresql/17.nix | 2026-09-07 | |
| `postgresql_18` (unstable) | **18.6** | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/servers/sql/postgresql/18.nix | 2026-09-07 | exactly the docker pin |
| `postgresql_19` (unstable) | 19beta3 | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/servers/sql/postgresql/19.nix | 2026-09-07 | beta; not a candidate |
| majors defined (unstable) | 14, 15, 16, 17, 18, 19 (plus `_jit` variants) | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/servers/sql/postgresql/default.nix | 2026-09-07 | |
| default `postgresql` attribute (unstable) | **`postgresql_18`** | `pkgs/top-level/all-packages.nix` line 7475 on master (`postgresql = postgresql_18;`), same on `nixos-unstable` | 2026-09-07 | changed from 17 after the 26.05 branch-off; NixOS module maps stateVersion >= 26.11 to 18 |
| default `postgresql` attribute (stable 26.05 and 25.11) | `postgresql_17` | `all-packages.nix` on `release-26.05` (line 7964) and `release-25.11` (line 9546) | 2026-09-07 | stable defines 14 through 18 only; no 19 |
| current stable NixOS release | 26.05 "Yarara", released 2026-05-30 | https://nixos.org/manual/nixos/stable/release-notes | 2026-09-07 | |

## 5. Release-binary fallback

| item | version found | where | checked | note |
|---|---|---|---|---|
| cerbos latest release | **v0.55.0**, published 2026-08-13, prerelease false | https://api.github.com/repos/cerbos/cerbos/releases/latest | 2026-09-07 | matches the docker pin; no newer release |
| cerbos server asset, linux x86_64 | `https://github.com/cerbos/cerbos/releases/download/v0.55.0/cerbos_0.55.0_Linux_x86_64.tar.gz` | same API response | 2026-09-07 | pattern: `cerbos_<ver>_<Linux|Darwin>_<x86_64|arm64|all>.tar.gz`; tag has `v`, filename does not; OS names are capitalized |
| cerbos server asset, darwin arm64 | `https://github.com/cerbos/cerbos/releases/download/v0.55.0/cerbos_0.55.0_Darwin_arm64.tar.gz` (also `_Darwin_all.tar.gz` universal) | same | 2026-09-07 | `cerbosctl_*` assets follow the same pattern; `.sbom.json` and Sigstore files exist per asset |
| openfga latest release | **v1.19.0**, published 2026-08-25, prerelease false (v1.18.3 on 2026-08-05 before it) | https://api.github.com/repos/openfga/openfga/releases/latest and https://api.github.com/repos/openfga/openfga/releases?per_page=3 | 2026-09-07 | matches the docker pin |
| openfga asset, linux x86_64 | `https://github.com/openfga/openfga/releases/download/v1.19.0/openfga_1.19.0_linux_amd64.tar.gz` | same | 2026-09-07 | pattern: `openfga_<ver>_<linux|darwin|windows>_<amd64|arm64|386>.tar.gz`, lowercase, `amd64` not `x86_64`; `checksums.txt` ships alongside |
| openfga asset, darwin arm64 | `https://github.com/openfga/openfga/releases/download/v1.19.0/openfga_1.19.0_darwin_arm64.tar.gz` | same | 2026-09-07 | |

## 6. services-flake / process-compose

| item | version found | where | checked | note |
|---|---|---|---|---|
| services-flake status | active; last commit 2026-08-18 ("feat(alloy): init"), 712 commits, maintainer shivaraj-bh | https://github.com/juspay/services-flake ; https://api.github.com/repos/juspay/services-flake/commits?per_page=1 | 2026-09-07 | still a process-compose-flake module on flake-parts; no deprecation notice at https://community.flake.parts/services-flake |
| postgres service | yes ("PostgreSQL", plus pgAdmin) | https://community.flake.parts/services-flake/services | 2026-09-07 | |
| cerbos / openfga service | **none** | same | 2026-09-07 | as expected; declare them as plain process-compose processes wrapping the binaries |

## 7. Hex packages (source: hex.pm API)

| item | version found | where | checked | note |
|---|---|---|---|---|
| muontrap | 2.0.0 (2026-08-13) | https://hex.pm/api/packages/muontrap | 2026-09-07 | **new major**; 1.8.0 was the last 1.x (2026-05-06). Check the changelog before assuming 1.x API |
| styler (adobe/elixir-styler) | 1.12.2 (2026-07-30) | https://hex.pm/api/packages/styler | 2026-09-07 | |
| mneme | 0.10.2 (2025-01-24) | https://hex.pm/api/packages/mneme | 2026-09-07 | no release in 19 months; verify it works on Elixir 1.20 |
| boundary | 0.10.4 (2024-09-25) | https://hex.pm/api/packages/boundary | 2026-09-07 | two years without a release |
| nimble_options | 1.1.1 (2024-05-25) | https://hex.pm/api/packages/nimble_options | 2026-09-07 | |
| stream_data | 1.4.0 (2026-07-14) | https://hex.pm/api/packages/stream_data | 2026-09-07 | |
| mox | 1.3.1 (2026-08-31) | https://hex.pm/api/packages/mox | 2026-09-07 | 1.3.0 and 1.3.1 both landed in the last two weeks |

## Recommendation

- **Lock `nixos-unstable`** (head `c043004d…`, 2026-09-05), not a stable branch. On it, `beam.packages.erlang_29.elixir_1_20` gives OTP **29.0.6** and Elixir **1.20.4**, which are the exact versions already in `.tool-versions`, so no overlay is needed and the TESTING.md placeholder `erlang_28` should become `erlang_29`. Stable 26.05 also has both patch versions, but its openfga is 1.14.2, so unstable is the branch that matches every pin at once.
- **Pin `postgresql_18`** (18.6 on unstable, the current docker pin) and write the attribute explicitly; do not rely on the bare `postgresql` alias, which is 18 on unstable but 17 on both stable branches. TESTING.md's "17 ⟨choose⟩" would be a downgrade from what the project runs today.
- **openfga from nixpkgs**: `pkgs.openfga` on unstable is 1.19.0, the same version as the docker pin and the current upstream release. Use it; keep the release-tarball fetch as a documented fallback only.
- **cerbos from fetched release binaries**: it is not in nixpkgs on any branch, so the flake needs a small `stdenvNoCC` derivation that `fetchurl`s the `cerbos_0.55.0_<OS>_<arch>.tar.gz` asset per system (Linux_x86_64, Linux_arm64, Darwin_arm64, Darwin_x86_64) with hashes recorded in the flake. Building from source with `buildGoModule` is the alternative, but the release tarball is simpler and matches the plan's "binaries on the path" wording. v0.55.0 is still the latest release.
- services-flake remains the right tool for `nix run .#services`; use its `postgres` service and add cerbos/openfga as hand-written process-compose processes, since no service module exists for either.
