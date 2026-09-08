defmodule Turnstile.Ledger.SchemaDump do
  @moduledoc """
  The mechanism behind `mix turnstile.schema_dump`: an ephemeral cluster,
  the caller's migrations run as the owner role, `pg_dump --schema-only`
  written to a file, the cluster stopped. The file is the teaching artifact
  a thin application commits under `priv/schema/`; `git diff --exit-code`
  on it is what proves the migrations produce the schema the repository
  shows.

  `pg_dump` 18 opens and closes its output with `\\restrict` and
  `\\unrestrict` lines carrying a random token; they are removed so the
  file is the same on every run.
  """

  use Boundary, top_level?: true, deps: [Turnstile.Test, Ecto.Migrator]

  alias Turnstile.Test.Cluster

  @schema NimbleOptions.new!(
            otp_app: [
              type: :atom,
              doc: "The application whose env receives the repo's config; the repo's own `otp_app` when absent."
            ],
            repo: [type: :atom, required: true, doc: "An owner-role repo module of the calling application."],
            output: [type: :string, required: true, doc: "The file to write, such as `priv/schema/rbac.sql`."],
            migrations: [
              type: {:or, [:string, {:list, {:tuple, [:integer, :atom]}}]},
              default: "priv/repo/migrations",
              doc: "A migrations directory, or `{version, module}` pairs."
            ]
          )

  @doc "Run the dump. Returns the path written. Options: #{NimbleOptions.docs(@schema)}"
  @spec dump(keyword()) :: Path.t()
  def dump(options) when is_list(options) do
    options = NimbleOptions.validate!(options, @schema)

    cluster =
      Cluster.start(
        otp_app: options[:otp_app] || options[:repo].config()[:otp_app],
        repos: [{options[:repo], role: :owner, database: :sandboxed, pool_size: 2}],
        migrate: &migrate!(&1, options[:migrations])
      )

    try do
      write!(options[:output], schema_sql(cluster))
    after
      Cluster.stop(cluster)
    end

    options[:output]
  end

  defp migrate!(repo, migrations) do
    _versions = Ecto.Migrator.run(repo, migrations, :up, all: true, log: false)
    :ok
  end

  defp schema_sql(%Cluster{} = cluster) do
    args = ["--schema-only", "-h", cluster.socket_dir, "-U", Cluster.role(:owner), Cluster.database(:sandboxed)]

    case System.cmd("pg_dump", args, stderr_to_stdout: true, env: [{"PGPASSWORD", nil}, {"PGOPTIONS", nil}]) do
      {output, 0} -> strip_restrict(output)
      {output, status} -> raise "pg_dump exited with #{status}: #{output}"
    end
  end

  defp strip_restrict(sql) do
    sql
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(&1, ["\\restrict ", "\\unrestrict "]))
    |> Enum.join("\n")
  end

  defp write!(path, sql) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, sql)
  end
end
