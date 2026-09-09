defmodule ExampleFga.Repo.Migrations.Rules do
  @moduledoc false
  use Ecto.Migration

  alias Turnstile.Fga.Migration

  # The rules of this binding are the model under `priv/fga`, which the server
  # holds and names by id, so the database holds no policy of its own. What it
  # does hold is how far the projector has drained the ledger into the store,
  # one row per store, which is the position every decision reports as the
  # state the engine could have seen.
  def up, do: Migration.checkpoint_up(app_role: "turnstile_app")
  def down, do: Migration.checkpoint_down()
end
