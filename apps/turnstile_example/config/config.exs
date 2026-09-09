import Config

# Phoenix reads its JSON library from the application environment; the
# example uses the one Elixir ships.
config :phoenix, :json_library, JSON

# Plugs in a pipeline are initialised at runtime, so a router does not
# depend on its plugs at compile time and a plug change recompiles one file.
config :phoenix, :plug_init_mode, :runtime
