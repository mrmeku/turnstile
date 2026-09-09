defmodule Turnstile.Ledger.ReviewTest.OneRow do
  @moduledoc false

  @behaviour Turnstile.Ledger.Review

  alias Turnstile.Ledger.Review.Row

  @impl Turnstile.Ledger.Review
  def rows(_options) do
    [%Row{subject: "account-00001", kind: :user, operation: :read, object: "folder:1", note: "reader"}]
  end
end

defmodule Turnstile.Ledger.ReviewTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Ledger.Review
  alias Turnstile.Ledger.ReviewTest.OneRow
  alias Turnstile.Ledger.TestSupport
  alias Turnstile.Ledger.TestSupport.Golden

  @golden "test/golden/review.txt"

  test "the review of today is the table the golden file holds, column by column" do
    table = Review.table(reporter: TestSupport.Review, at: nil)

    assert table == Golden.read!(@golden, table)
  end

  test "the columns are the ones a reviewer reads across, in order" do
    assert Review.columns() == ["subject", "kind", "operation", "object", "note"]
  end

  test "a review asked about a date says which date it answered for" do
    table = Review.table(reporter: TestSupport.Review, at: ~D[2026-03-01])

    assert table =~ "who can do what, on 2026-03-01: 2 rows"
    assert table =~ "as of 2026-03-01"
  end

  test "a review of one row counts one row" do
    assert Review.table(reporter: OneRow, at: nil) =~ "who can do what, today: 1 row\n"
  end

  test "a review with no reporter says where the reporter is named" do
    assert_raise Error.Invalid, ~r/name the module answering the review in mix.exs/, fn -> Review.table([]) end
  end
end
