import Config

# The ledger keeps fact values in jsonb columns. Postgrex reads the library
# it encodes and decodes json with from this key at runtime, and Elixir's own
# JSON module is what this package uses, so no json dependency is added for
# it.
config :postgrex, :json_library, JSON
