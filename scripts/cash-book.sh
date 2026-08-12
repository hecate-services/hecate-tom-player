#!/usr/bin/env bash
#
# THE CASH BOOK OF A HOUSE, FROM A SHELL.
#
#   scripts/cash-book.sh <path to house.log>
#
# Replays a house's ledger through the aggregate and prints the account: what it
# opened with, every movement since, and the balance each one left behind.
#
# IT OPENS THE FILE FOR READING ONLY, which is why `tom_ledger:read/1' exists
# beside `open/1'. Point it at the ledger of a house that is up and trading and
# nothing is disturbed: the reader takes no lock, appends nothing, and repairs
# nothing. A partial record at the tail is simply not read, which is the same
# thing the house itself will do to it on its next boot.
#
# The last two lines are the point. `closing' is reached by adding the movements
# up from the opening balance; `purse' is reached by moving one number on every
# settlement. They are the same question answered by two routes, and if they ever
# disagree that is worth an evening.

set -euo pipefail

house="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ledger="${1:-}"

[ -n "$ledger" ] || {
    printf 'usage: %s <path to house.log>\n' "$(basename "$0")" >&2
    exit 2
}

[ -r "$ledger" ] || {
    printf 'no ledger to read at %s\n' "$ledger" >&2
    exit 1
}

libs="${house}/_build/default/lib"

[ -d "${libs}/hecate_tom_house/ebin" ] || {
    printf 'nothing built yet. Run: rebar3 compile\n' >&2
    exit 1
}

LEDGER="$ledger" erl -noshell -pa "${libs}"/*/ebin -eval '
    {ok, Facts} = tom_ledger:read(os:getenv("LEDGER")),
    House = tom_house:replay(Facts, tom_house:empty()),
    #{opened_with := Opened, entries := Entries, closing := Closing} =
        tom_house:cash_book(House),

    Clock = fun(Ms) ->
                {_D, {H, M, S}} = calendar:system_time_to_local_time(Ms, millisecond),
                io_lib:format("~2..0b:~2..0b:~2..0b", [H, M, S])
            end,
    Word  = fun(purchase) -> "Bought"; (sale) -> "Sold" end,
    Signed = fun(purchase, Coin) -> -Coin; (sale, Coin) -> Coin end,
    What  = fun(E) ->
                io_lib:format("~s ~s of ~s at ~s",
                              [Word(maps:get(kind, E)),
                               io_lib:format("~.3f", [maps:get(tons, E)]),
                               tom_names:local(maps:get(good, E)),
                               tom_names:local(maps:get(harbour, E))])
            end,

    io:format("~n  ~-12s ~-42s ~11s ~12s~n",
              ["", "the house opened", "", io_lib:format("~.2f", [Opened])]),
    [io:format("  ~-12s ~-42ts ~11.2f ~12.2f~n",
               [Clock(maps:get(at, E)), What(E),
                Signed(maps:get(kind, E), maps:get(coin, E)),
                maps:get(balance, E)])
     || E <- Entries],
    io:format("~n  ~-12s ~-42s ~11s ~12.2f~n", ["", "closing", "", Closing]),
    io:format("  ~-12s ~-42s ~11s ~12.2f~n~n", ["", "purse", "", tom_house:purse(House)]),
    init:stop().
'
