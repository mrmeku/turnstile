defmodule Mix.Tasks.Turnstile.ReviewTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Turnstile.Review

  @golden "test/golden/review.txt"

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "it prints the review the reporter named in mix.exs answers, for today" do
    Review.run([])

    assert_received {:mix_shell, :info, [table]}
    assert table == File.read!(@golden)
  end

  test "it prints the review of the date it was asked about" do
    Review.run(["--at", "2026-03-01"])

    assert_received {:mix_shell, :info, [table]}
    assert table =~ "who can do what, on 2026-03-01: 2 rows"
    assert table =~ "as of 2026-03-01"
  end

  test "a date it cannot read says what a date looks like" do
    assert_raise Mix.Error, ~r/takes a date as YYYY-MM-DD/, fn -> Review.run(["--at", "March"]) end
  end

  test "an argument it does not know says which arguments it takes" do
    assert_raise Mix.Error, ~r/takes --at <date> or nothing/, fn -> Review.run(["--since", "2026-03-01"]) end
  end
end
