%% @doc The log, including the case it exists for: a crash in the middle of a
%% write.
-module(tom_ledger_tests).

-include_lib("eunit/include/eunit.hrl").

an_absent_log_is_an_empty_history_test() ->
    Path = a_path(),
    {ok, Ledger, Facts} = tom_ledger:open(Path),
    ?assertEqual([], Facts),
    ok = tom_ledger:close(Ledger).

what_goes_in_comes_back_in_order_test() ->
    Path = a_path(),
    {ok, Ledger, []} = tom_ledger:open(Path),
    ok = tom_ledger:append(Ledger, {house_opened_v1, #{purse => 1000.0}}),
    ok = tom_ledger:append(Ledger, {purchase_ordered_v1, #{order => <<"a">>}}),
    ok = tom_ledger:append(Ledger, {purchase_settled_v1, #{order => <<"a">>}}),
    ok = tom_ledger:close(Ledger),
    {ok, Reopened, Facts} = tom_ledger:open(Path),
    ok = tom_ledger:close(Reopened),
    ?assertMatch([{house_opened_v1, _}, {purchase_ordered_v1, _},
                  {purchase_settled_v1, _}], Facts).

reading_without_opening_test() ->
    Path = a_path(),
    {ok, Ledger, []} = tom_ledger:open(Path),
    ok = tom_ledger:append(Ledger, {house_opened_v1, #{purse => 1.0}}),
    ok = tom_ledger:close(Ledger),
    ?assertMatch({ok, [{house_opened_v1, _}]}, tom_ledger:read(Path)).

%% THE CASE THIS MODULE EXISTS FOR. A write interrupted halfway leaves a stub.
%% Everything before it is history; the stub is not, and it must be cut off
%% rather than appended to, or the next record runs on after it and the whole
%% history behind it becomes unreadable.
a_half_written_record_is_cut_off_test() ->
    Path = a_path(),
    {ok, Ledger, []} = tom_ledger:open(Path),
    ok = tom_ledger:append(Ledger, {house_opened_v1, #{purse => 1000.0}}),
    ok = tom_ledger:append(Ledger, {purchase_ordered_v1, #{order => <<"a">>}}),
    ok = tom_ledger:close(Ledger),
    ok = maim(Path, 9),

    {ok, Repaired, Facts} = tom_ledger:open(Path),
    ?assertMatch([{house_opened_v1, _}], Facts),

    %% And the repaired log takes a new record that reads back cleanly, which is
    %% the part that would have been lost had the stub been left in place.
    ok = tom_ledger:append(Repaired, {purchase_ordered_v1, #{order => <<"b">>}}),
    ok = tom_ledger:close(Repaired),
    {ok, Again, Recovered} = tom_ledger:open(Path),
    ok = tom_ledger:close(Again),
    ?assertMatch([{house_opened_v1, _}, {purchase_ordered_v1, #{order := <<"b">>}}],
                 Recovered).

%% A length prefix that promises more bytes than are there is the same fault
%% seen a moment earlier.
a_truncated_length_prefix_is_cut_off_test() ->
    Path = a_path(),
    {ok, Ledger, []} = tom_ledger:open(Path),
    ok = tom_ledger:append(Ledger, {house_opened_v1, #{purse => 1000.0}}),
    ok = tom_ledger:close(Ledger),
    {ok, Whole} = file:read_file(Path),
    ok = file:write_file(Path, <<Whole/binary, 0, 0>>),
    {ok, Repaired, Facts} = tom_ledger:open(Path),
    ok = tom_ledger:close(Repaired),
    ?assertMatch([{house_opened_v1, _}], Facts).

%%% Helpers

%% Lop bytes off the end, the way a power cut does.
maim(Path, Bytes) ->
    {ok, Whole} = file:read_file(Path),
    file:write_file(Path, binary:part(Whole, 0, byte_size(Whole) - Bytes)).

%% A fresh directory every time, per run and per test. `unique_integer' alone
%% restarts from a small number in every new VM, so two consecutive runs of the
%% suite would share a ledger and the second would start rich.
a_path() ->
    Unique = erlang:phash2({erlang:system_time(nanosecond),
                            erlang:unique_integer([positive])}),
    filename:join([os:getenv("TMPDIR", "/tmp"),
                   "hecate_tom_house_test",
                   integer_to_list(Unique),
                   "house.log"]).
