defmodule Example.Migrations.Domain do
  @moduledoc """
  The domain tables, as a helper a thin application's first migration
  calls. The library ships no migration files. Every table receives the
  application role's grants; no foreign key cascades into a fact schema,
  so a revocation deletes nothing but the fact.

      defmodule ExampleRbac.Repo.Migrations.Domain do
        use Ecto.Migration
        def up, do: Example.Migrations.Domain.up(app_role: "turnstile_app")
        def down, do: Example.Migrations.Domain.down()
      end
  """

  import Ecto.Migration

  @schema NimbleOptions.new!(
            app_role: [
              type: :string,
              default: "turnstile_app",
              doc: "The database role the application connects as, which receives the grants."
            ]
          )

  @serial_tables ~w(agencies offices programs account_roles assignments office_roles documents markings portions
    marking_proposals override_reports)a
  @keyed_tables ~w(users categories)a

  @doc "Create the domain tables and the grants. Options: #{NimbleOptions.docs(@schema)}"
  @spec up(keyword()) :: :ok
  def up(options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @schema)
    tenancy()
    accounts()
    roles()
    documents()
    proposals_and_reports()
    grants(options[:app_role])
    :ok
  end

  @doc "The tables the helper creates, as the schemas name them."
  @spec tables() :: [String.t()]
  def tables, do: Enum.map(@serial_tables ++ @keyed_tables, &Atom.to_string/1)

  @doc "Drop the domain tables, dependents first."
  @spec down() :: :ok
  def down do
    Enum.each(Enum.reverse(@serial_tables ++ @keyed_tables), &drop(table(&1)))
    :ok
  end

  defp tenancy do
    create table(:agencies) do
      add :name, :text, null: false
      add :nationality, :text, null: false
    end

    create table(:offices) do
      add :name, :text, null: false
      add :agency_id, references(:agencies), null: false
    end

    create table(:programs) do
      add :name, :text, null: false
      add :closed_at, :utc_datetime
      add :office_id, references(:offices), null: false
    end

    create table(:categories, primary_key: false) do
      add :name, :text, primary_key: true
      add :specified, :boolean, null: false, default: false
      add :implied_controls, {:array, :text}, null: false, default: []
    end
  end

  defp accounts do
    create table(:users, primary_key: false) do
      add :id, :text, primary_key: true
      add :name, :text, null: false
      add :kind, :text, null: false
      add :person_id, :text, null: false
      add :employment, :text, null: false
      add :nationality, :text, null: false
    end

    create table(:account_roles) do
      add :user_id, references(:users, type: :text), null: false
      add :role, :text, null: false
    end

    create unique_index(:account_roles, [:user_id, :role])
  end

  defp roles do
    create table(:assignments) do
      add :user_id, references(:users, type: :text), null: false
      add :program_id, references(:programs), null: false
      add :role, :text, null: false
    end

    create unique_index(:assignments, [:user_id, :program_id])

    create table(:office_roles) do
      add :user_id, references(:users, type: :text), null: false
      add :office_id, references(:offices), null: false
      add :role, :text, null: false
    end

    create unique_index(:office_roles, [:user_id, :office_id, :role])
  end

  defp documents do
    create table(:documents) do
      add :title, :text, null: false
      add :decontrol, :utc_datetime
      add :program_id, references(:programs), null: false
      add :designating_office_id, references(:offices), null: false
    end

    create table(:markings) do
      add :document_id, references(:documents), null: false
      add :categories, {:array, :text}, null: false, default: []
      add :controls, {:array, :text}, null: false, default: []
      add :releasable_to, {:array, :text}, null: false, default: []
      add :list, {:array, :text}, null: false, default: []
    end

    create unique_index(:markings, [:document_id])

    create table(:portions) do
      add :document_id, references(:documents), null: false
      add :body, :text, null: false
      add :categories, {:array, :text}, null: false, default: []
      add :controls, {:array, :text}, null: false, default: []
      add :releasable_to, {:array, :text}, null: false, default: []
    end
  end

  defp proposals_and_reports do
    create table(:marking_proposals) do
      add :document_id, references(:documents), null: false
      add :proposer_id, references(:users, type: :text), null: false
      add :approver_id, references(:users, type: :text)
      add :status, :text, null: false, default: "pending"
      add :categories, {:array, :text}, null: false, default: []
      add :controls, {:array, :text}, null: false, default: []
      add :releasable_to, {:array, :text}, null: false, default: []
      add :list, {:array, :text}, null: false, default: []
    end

    create table(:override_reports) do
      add :document_id, references(:documents), null: false
      add :office_id, references(:offices), null: false
      add :user_id, references(:users, type: :text), null: false
      add :justification, :text, null: false
      add :operation_id, :text, null: false
      add :at, :utc_datetime, null: false
    end
  end

  defp grants(app_role) do
    for name <- @serial_tables ++ @keyed_tables do
      execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{name} TO #{app_role}"
    end

    for name <- @serial_tables do
      execute "GRANT USAGE, SELECT ON SEQUENCE #{name}_id_seq TO #{app_role}"
    end
  end
end
