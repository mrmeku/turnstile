defmodule ExampleFga.Repo.Migrations.Rules do
  @moduledoc false
  use Ecto.Migration

  alias Turnstile.Fga.Migration
  alias Turnstile.Fga.Relay

  # The rules of this binding are the model under `priv/fga`, which the server
  # holds and names by id, so the database holds no policy of its own. What it
  # does hold is the drain: one marker per object a write may have moved the
  # store behind on, and the cursor saying how far the runner delivering them
  # has got.
  def up do
    :ok = Migration.outbox_up(app_role: "turnstile_app")
    :ok = Relay.Migration.cursor_up(app_role: "turnstile_app")
  end

  def down do
    :ok = Relay.Migration.cursor_down()
    :ok = Migration.outbox_down()
  end
end
