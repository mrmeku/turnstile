defmodule ExamplePostgres.Policies do
  @moduledoc """
  The example's rules of `docs/reference.md` §3 as Postgres policy
  expressions. Each function answers one SQL fragment, and the migration
  hands those fragments to `Turnstile.Postgres.Migration`. Every fact a
  fragment reads is read from the tables at the moment the statement runs,
  so a revoked row stops granting on the next statement.

  The subject and the moment come from the session settings the adapter
  sets around every call: `turnstile.subject_id`, `turnstile.now`, and the
  `turnstile.reauthenticated_at` fact the caller supplied. A setting the
  caller did not supply reads as `NULL`, and a predicate over `NULL` is not
  true, so an absent fact denies.

  A policy on `portions` reads its document's program, designating office,
  and decontrol date through the accessor functions rather than through
  `documents`. Under the `read` operation the document's own policy narrows
  every reference to that table, and a portion of a document the banner
  blocks would then disappear with its document; the accessors run as the
  table's owner, which the owner's exemption policy admits, so the portion
  answers under its own marking.
  """

  alias Example.Document
  alias Example.Marking
  alias Example.Portion
  alias Example.Proposal

  @app_role "turnstile_app"
  @owner_role "turnstile_owner"

  @subject "current_setting('turnstile.subject_id', true)"
  @now "nullif(current_setting('turnstile.now', true), '')::timestamp"
  @reauthenticated "nullif(current_setting('turnstile.reauthenticated_at', true), '')::timestamp"
  @window "interval '900 seconds'"
  @fresh "(#{@now} - #{@reauthenticated}) BETWEEN interval '0 second' AND #{@window}"

  @program "turnstile_document_program"
  @office "turnstile_document_office"
  @decontrol "turnstile_document_decontrol"

  @accessors [
    {@program, "bigint", "program_id"},
    {@office, "bigint", "designating_office_id"},
    {@decontrol, "timestamp", "decontrol"}
  ]

  @controls ~w(federal_only no_foreign releasable_to named_list)
  @readers ~w(lead member)
  @designator ~w(designator)
  @approver ~w(approver)
  @office_readers ~w(designator approver)

  @doc "The tables the policies protect, which are the tables the version is read back from."
  @spec protected() :: [String.t()]
  def protected, do: ~w(documents markings portions marking_proposals)

  @doc "The schemas the binding names: the four whose tables the policies protect."
  @spec schemas() :: [module()]
  def schemas, do: [Document, Marking, Portion, Proposal]

  @doc "The database role the application connects as."
  @spec app_role() :: String.t()
  def app_role, do: @app_role

  @doc "The database role that owns the protected tables and runs the migrations."
  @spec owner_role() :: String.t()
  def owner_role, do: @owner_role

  @doc "The assignment roles that reach a document at all, which is every one of them."
  @spec readers() :: [String.t()]
  def readers, do: @readers

  @doc "The accessor functions a policy on `portions` reads its document through, with their grants."
  @spec accessors() :: [String.t()]
  def accessors, do: Enum.flat_map(@accessors, &accessor/1)

  @doc "The same functions dropped."
  @spec accessor_drops() :: [String.t()]
  def accessor_drops, do: Enum.map(@accessors, fn {name, _type, _column} -> "DROP FUNCTION #{name}(bigint)" end)

  @doc "The `SELECT` policy of `read` on `documents`, for the assignment roles that hold it."
  @spec document_read([String.t()]) :: String.t()
  def document_read(roles) when is_list(roles) do
    "(#{document_purpose(roles)}) AND NOT (#{document_blocked()})"
  end

  @doc "The `SELECT` policy of `read_redacted` on `documents`: lawful purpose alone."
  @spec document_read_redacted() :: String.t()
  def document_read_redacted, do: document_purpose(@readers)

  @doc "A designator of the designating office."
  @spec document_designator() :: String.t()
  def document_designator, do: holds("documents.designating_office_id", @designator)

  @doc "An approver of the designating office."
  @spec document_approver() :: String.t()
  def document_approver, do: holds("documents.designating_office_id", @approver)

  @doc "A designator of the designating office in a session that re-authenticated inside the window."
  @spec document_marks() :: String.t()
  def document_marks, do: "(#{document_designator()}) AND (#{@fresh})"

  @doc "The `SELECT` policy of `read` on `portions`: the document's purpose and the portion's own marking."
  @spec portion_read() :: String.t()
  def portion_read, do: "(#{portion_purpose()}) AND NOT (#{portion_blocked()})"

  @doc "A designator of the portion's document's office in a fresh session."
  @spec portion_marks() :: String.t()
  def portion_marks do
    "(#{holds("#{@office}(portions.document_id)", @designator)}) AND (#{@fresh})"
  end

  @doc "A designator of the document's office, which is who may propose."
  @spec proposal_proposer() :: String.t()
  def proposal_proposer, do: holds("#{@office}(marking_proposals.document_id)", @designator)

  @doc "An approver of the document's office who is not the proposer."
  @spec proposal_approver() :: String.t()
  def proposal_approver do
    approver = holds("#{@office}(marking_proposals.document_id)", @approver)
    "(#{approver}) AND marking_proposals.proposer_id <> #{@subject}"
  end

  @doc "The row a proposal insert may write: the subject's own, on a document the subject designates."
  @spec proposal_written() :: String.t()
  def proposal_written do
    "(#{proposal_proposer()}) AND marking_proposals.proposer_id = #{@subject}"
  end

  @doc "The banner a designator may write in a fresh session."
  @spec marking_marks() :: String.t()
  def marking_marks do
    "(#{holds("#{@office}(markings.document_id)", @designator)}) AND (#{@fresh})"
  end

  @doc """
  The banner an approval may write: an approver of the document's office,
  where a pending proposal on that document was made by somebody else. The
  proposal's own row is written after its document's, so at this moment it
  is still pending.
  """
  @spec marking_approves() :: String.t()
  def marking_approves do
    approver = holds("#{@office}(markings.document_id)", @approver)

    """
    (#{approver}) AND EXISTS (
      SELECT 1 FROM marking_proposals p
      WHERE p.document_id = markings.document_id
        AND p.status = 'pending'
        AND p.proposer_id <> #{@subject}
    )
    """
  end

  defp accessor({name, type, column}) do
    [
      """
      CREATE FUNCTION #{name}(document bigint) RETURNS #{type}
        LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
        AS 'SELECT #{column} FROM documents WHERE id = document'
      """,
      "REVOKE EXECUTE ON FUNCTION #{name}(bigint) FROM PUBLIC",
      "GRANT EXECUTE ON FUNCTION #{name}(bigint) TO #{@app_role}, #{@owner_role}"
    ]
  end

  # Lawful purpose: an assignment to the document's program while that
  # program is open, or a role in the office that designated it.
  defp document_purpose(roles) do
    "#{assigned("documents.program_id", roles)} OR #{holds("documents.designating_office_id", @office_readers)}"
  end

  defp portion_purpose do
    assigned = assigned("#{@program}(portions.document_id)", @readers)
    "#{assigned} OR #{holds("#{@office}(portions.document_id)", @office_readers)}"
  end

  defp assigned(program, roles) do
    """
    EXISTS (
      SELECT 1 FROM assignments a
      JOIN programs p ON p.id = a.program_id
      WHERE a.user_id = #{@subject}
        AND a.program_id = #{program}
        AND a.role = ANY (ARRAY[#{quoted(roles)}])
        AND p.closed_at IS NULL
    )
    """
  end

  defp holds(office, roles) do
    """
    EXISTS (
      SELECT 1 FROM office_roles r
      WHERE r.user_id = #{@subject}
        AND r.office_id = #{office}
        AND r.role = ANY (ARRAY[#{quoted(roles)}])
    )
    """
  end

  # While the document is controlled, an effective control of its banner
  # that the subject does not clear.
  defp document_blocked do
    """
    EXISTS (
      SELECT 1
      FROM markings m
      JOIN offices o ON o.id = documents.designating_office_id
      JOIN agencies g ON g.id = o.agency_id
      JOIN users u ON u.id = #{@subject}
      LEFT JOIN categories c ON c.name = ANY (m.categories) AND c.specified
      WHERE m.document_id = documents.id
        AND (documents.decontrol IS NULL OR documents.decontrol > #{@now})
        AND (#{fails("m", "m")})
    )
    """
  end

  # The same on a portion: its own controls and categories, under its
  # document's list and decontrol date.
  defp portion_blocked do
    """
    EXISTS (
      SELECT 1
      FROM markings dm
      JOIN offices o ON o.id = #{@office}(portions.document_id)
      JOIN agencies g ON g.id = o.agency_id
      JOIN users u ON u.id = #{@subject}
      LEFT JOIN categories c ON c.name = ANY (portions.categories) AND c.specified
      WHERE dm.document_id = portions.document_id
        AND (#{@decontrol}(portions.document_id) IS NULL OR #{@decontrol}(portions.document_id) > #{@now})
        AND (#{fails("portions", "dm")})
    )
    """
  end

  defp fails(marking, listed) do
    Enum.map_join(@controls, " OR ", &"(#{effective(&1, marking)} AND #{test(&1, marking, listed)})")
  end

  defp test("federal_only", _marking, _listed), do: "u.employment <> 'federal'"
  defp test("no_foreign", _marking, _listed), do: "u.nationality <> g.nationality"
  defp test("releasable_to", marking, _listed), do: "NOT (u.nationality = ANY (#{marking}.releasable_to))"
  defp test("named_list", _marking, listed), do: "NOT (#{@subject} = ANY (#{listed}.list))"

  # A control is effective when the marking declares it or a specified
  # category the marking names implies it. Nothing is copied.
  defp effective(control, marking) do
    "('#{control}' = ANY (#{marking}.controls) OR '#{control}' = ANY (c.implied_controls))"
  end

  defp quoted(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
