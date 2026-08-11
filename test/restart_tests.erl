%% @doc THE POINT OF THE WHOLE ARCHITECTURE, tested.
%%
%% A house is shut down completely, a voyage happens while it is not running,
%% and it comes back and finds its ship at the far port with the cargo aboard
%% and the purse exactly where it left it. Nothing was pushed at it while it was
%% away and nothing was queued for it: it asks three questions and is right
%% again.
%%
%% The harder case is an order that was IN FLIGHT when the house died. It is
%% re-called under the original key, the harbour replays the receipt it stored,
%% and the purse moves exactly once no matter how many times the retry runs.
-module(restart_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SHIP, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(HOUSE, <<"mri:instance:io.macula/tom/house/raf">>).
-define(OCEAN, <<"mri:instance:io.macula/tom/ocean">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).
-define(PEPPER, <<"mri:class:io.macula/tom/good/pepper">>).

%% Pepper at Macao, per ton, for a quay deep enough that the walk does not
%% matter to the arithmetic under test. Forty tons cost 581.42.
-define(A_TON_OF_PEPPER, 14.5355).

house_test_() ->
    {foreach, fun a_path/0, fun shut_any/1,
     [fun a_voyage_survives_a_shutdown/1,
      fun a_cold_boot_keeps_what_it_knew/1,
      fun an_order_in_flight_settles_on_the_way_back/1,
      fun sweeping_a_settled_house_moves_nothing/1,
      fun the_page_and_the_sweep_race/1,
      fun a_refusal_closes_the_order_for_good/1,
      fun the_purse_is_seeded_once/1,
      fun a_purse_that_will_not_stretch/1,
      fun the_hold_is_the_harbours_to_refuse/1,
      fun nothing_is_bought_from_a_ship_at_sea/1]}.

%%% ===================================================================
%%% Buy at one port, sail, die, come back, find her, sell at the other
%%% ===================================================================

a_voyage_survives_a_shutdown(Ledger) ->
    {"a house shut down for a whole voyage finds its ship at the far port",
     fun() ->
        %% --- first life: alongside at Macao ---------------------------------
        at_macao(),
        First = open(Ledger),
        ok = look(),
        ?assertMatch(#{standing := moored, where := ?MACAO}, sight()),

        {ok, _Receipt} = buy_cargo:order(?PEPPER, 40.0),
        ?assertEqual(418.58, purse()),
        ?assertEqual(#{?PEPPER => 40.0}, cargo()),

        {ok, _Consigned} = sail_ship:to(?LISBON),
        ?assertMatch(#{standing := consigned, bound_for := ?LISBON}, sight()),
        shut(First),

        %% --- the crossing happens with nobody at home -----------------------
        at_lisbon(),

        %% --- second life ----------------------------------------------------
        Second = open(Ledger),

        %% The purse is a fold of the log, so it is right before anybody has
        %% been asked anything at all.
        ?assertEqual(418.58, purse()),

        %% And the last picture it had of the ship is still there.
        ?assertMatch(#{standing := consigned, where := ?MACAO}, sight()),

        %% Three questions, and the house is right again.
        ok = look(),
        ?assertMatch(#{standing := moored, where := ?LISBON}, sight()),
        ?assertEqual(#{?PEPPER => 40.0}, cargo()),

        {ok, _Sold} = sell_cargo:order(?PEPPER, 40.0),
        ?assertEqual(1318.58, purse()),
        ?assertEqual(#{}, cargo()),
        shut(Second)
     end}.

%% A house that comes up with nothing answering keeps its money and its last
%% picture and says nothing new. It does not blank the page and it does not
%% invent a position.
a_cold_boot_keeps_what_it_knew(Ledger) ->
    {"a cold boot with nobody answering keeps the purse and the last picture",
     fun() ->
        at_macao(),
        First = open(Ledger),
        ok = look(),
        {ok, _} = buy_cargo:order(?PEPPER, 40.0),
        shut(First),

        silence(),
        Second = open(Ledger),
        ?assertEqual(418.58, purse()),
        ?assertMatch(#{standing := moored, where := ?MACAO}, sight()),
        ?assertMatch({no_news, _}, find_ship:look_around(names())),
        ?assertMatch(#{standing := moored, where := ?MACAO}, sight()),
        shut(Second)
     end}.

%%% ===================================================================
%%% An order in flight when the house died
%%% ===================================================================

an_order_in_flight_settles_on_the_way_back(Ledger) ->
    {"an order left in flight by a crash is settled under its original key",
     fun() ->
        %% --- first life: the port takes the order and never answers ---------
        at_macao(),
        First = open(Ledger),
        ok = look(),
        silent_on_buying(),
        {pending, _Why} = buy_cargo:order(?PEPPER, 40.0),

        %% The intent is on disk and no money has moved.
        ?assertEqual(1000.0, purse()),
        [#{order := Key, state := ordered}] = unsettled(),
        shut(First),

        %% --- second life: the port replays the receipt it stored ------------
        replaying_the_receipt(),
        Second = open(Ledger),
        ?assertMatch([#{order := Key}], unsettled()),

        ok = settle_orders:resume(),
        ?assertEqual(418.58, purse()),
        ?assertEqual([], unsettled()),

        %% The retry went out under the ORIGINAL key. That is the whole reason
        %% the harbour can tell a repeat from a second purchase.
        ?assertMatch([#{<<"order">> := Key}], tom_wire_fake:calls_to(<<"buy_cargo">>)),
        shut(Second)
     end}.

%% Sweeping again after everything is settled is worth nothing, which is what
%% lets the sweep run on a timer forever without anybody thinking about it.
sweeping_a_settled_house_moves_nothing(Ledger) ->
    {"sweeping a settled house moves nothing",
     fun() ->
        at_macao(),
        Keeper = open(Ledger),
        ok = look(),
        {ok, _} = buy_cargo:order(?PEPPER, 40.0),
        ?assertEqual(418.58, purse()),
        ok = settle_orders:resume(),
        ok = settle_orders:resume(),
        ?assertEqual(418.58, purse()),
        shut(Keeper)
     end}.

%% The page and the timer can settle the same order at the same instant. Both
%% get the same replayed receipt and the purse moves once.
the_page_and_the_sweep_race(Ledger) ->
    {"the page and the sweep settling at once move the purse once",
     fun() ->
        at_macao(),
        Keeper = open(Ledger),
        ok = look(),
        silent_on_buying(),
        {pending, _} = buy_cargo:order(?PEPPER, 40.0),
        [Order] = unsettled(),

        replaying_the_receipt(),
        Me = self(),
        Racers = [spawn(fun() ->
                                _ = buy_cargo:settle(Order),
                                Me ! {done, self()}
                        end) || _ <- lists:seq(1, 4)],
        _ = [receive {done, Pid} -> ok after 5000 -> error(timeout) end
             || Pid <- Racers],

        ?assertEqual(418.58, purse()),
        shut(Keeper)
     end}.

%% A refusal is FINAL. The order closes, no money moves, and no amount of
%% sweeping re-asks a harbour that has already said no.
a_refusal_closes_the_order_for_good(Ledger) ->
    {"a refusal closes an order and is never retried",
     fun() ->
        at_macao(),
        Keeper = open(Ledger),
        ok = look(),
        refusing_to_sell(),
        {refused, _Why} = sell_cargo:order(?PEPPER, 40.0),
        ?assertEqual(1000.0, purse()),
        ?assertEqual([], unsettled()),
        Before = length(tom_wire_fake:calls_to(<<"sell_cargo">>)),
        ok = settle_orders:resume(),
        ?assertEqual(Before, length(tom_wire_fake:calls_to(<<"sell_cargo">>))),
        shut(Keeper)
     end}.

%% Genesis applies once. A house that re-seeded its purse on every boot would
%% mint money by crashing.
the_purse_is_seeded_once(Ledger) ->
    {"the genesis purse applies once and never again",
     fun() ->
        at_macao(),
        First = open(Ledger),
        ok = look(),
        {ok, _} = buy_cargo:order(?PEPPER, 40.0),
        shut(First),
        Second = open(Ledger),
        ?assertEqual(418.58, purse()),
        shut(Second),
        Third = open(Ledger),
        ?assertEqual(418.58, purse()),
        shut(Third)
     end}.

%% The purse is checked here because this house owns the purse. Nothing is sent
%% to the harbour at all.
a_purse_that_will_not_stretch(Ledger) ->
    {"an order the purse will not cover is refused without troubling the port",
     fun() ->
        at_macao(),
        Keeper = open(Ledger),
        ok = look(),
        ?assertMatch({refused, {not_enough_coin, _}}, buy_cargo:order(?PEPPER, 4000.0)),
        ?assertEqual(1000.0, purse()),
        ?assertEqual([], tom_wire_fake:calls_to(<<"buy_cargo">>)),
        shut(Keeper)
     end}.

%% The hold is NOT checked here even though the house has a picture of it. The
%% harbour owns the ship while it is moored and its picture is the true one, so
%% refusing a legal purchase against a stale local copy would be worse than a
%% round trip. Here the local picture says ten tons free and the order is sixty:
%% it still goes out, and the harbour is the one that says no.
the_hold_is_the_harbours_to_refuse(Ledger) ->
    {"a full hold is the harbour's to refuse, not the house's to guess",
     fun() ->
        nearly_full_at_macao(),
        Keeper = open(Ledger),
        ok = look(),
        ?assertEqual(10.0, tom_house:free_hold(keep_house:house())),
        ?assertMatch({refused, _}, buy_cargo:order(?PEPPER, 60.0)),
        ?assertEqual(1, length(tom_wire_fake:calls_to(<<"buy_cargo">>))),
        shut(Keeper)
     end}.

%% A ship at sea is not at a quay, and this house can say so without troubling
%% anybody.
nothing_is_bought_from_a_ship_at_sea(Ledger) ->
    {"nothing can be bought from, sold out of, or sailed from a ship at sea",
     fun() ->
        at_sea(),
        Keeper = open(Ledger),
        ok = look(),
        ?assertMatch({refused, {ship_is_not_alongside, in_passage}},
                     buy_cargo:order(?PEPPER, 10.0)),
        ?assertMatch({refused, {ship_is_not_alongside, in_passage}},
                     sell_cargo:order(?PEPPER, 10.0)),
        ?assertMatch({refused, {ship_is_not_alongside, in_passage}},
                     sail_ship:to(?LISBON)),
        ?assertEqual([], tom_wire_fake:calls_to(<<"buy_cargo">>)),
        shut(Keeper)
     end}.

%%% ===================================================================
%%% The house, opened and shut
%%% ===================================================================

open(Ledger) ->
    {ok, Pid} = keep_house:start_link(#{names  => names(),
                                        ledger => Ledger,
                                        purse  => 1000.0}),
    Pid.

shut(Pid) ->
    gen_server:stop(Pid),
    ok.

%% Runs whatever the test did or did not reach. A failed assertion leaves eunit's
%% process alive and the keeper linked to it, so without this the next test finds
%% a house already open.
shut_any(_Ledger) ->
    tom_wire_fake:forget(),
    stopped(erlang:whereis(keep_house)).

%% A failing test takes its own process down and the keeper is linked to it, so
%% by the time this runs the pid from whereis may already be gone. Both are a
%% clean house.
stopped(undefined) ->
    ok;
stopped(Pid) ->
    try gen_server:stop(Pid)
    catch exit:noproc -> ok
    end.

%% One round of asking, run in the test's own process. The gen_server around it
%% is a timer; this is the behaviour.
look() ->
    {sight, Sight} = find_ship:look_around(names()),
    keep_house:sight(Sight).

sight() -> tom_house:sight(keep_house:house()).

cargo() -> tom_house:cargo(keep_house:house()).

unsettled() -> tom_house:unsettled(keep_house:house()).

purse() -> round2(tom_house:purse(keep_house:house())).

round2(F) -> round(F * 100) / 100.

names() ->
    {ok, Names} = tom_names:read(#{realm_name => <<"io.macula">>,
                                   player     => <<"raf">>,
                                   ship       => <<"santa_clara">>,
                                   harbours   => [<<"macao">>, <<"lisbon">>],
                                   goods      => [<<"pepper">>, <<"nutmeg">>]}),
    Names.

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

%%% ===================================================================
%%% The world, scripted
%%% ===================================================================

at_macao() ->
    answering(macao(#{})).

nearly_full_at_macao() ->
    answering(maps:merge(
                macao(#{?PEPPER => 190.0}),
                #{at(?MACAO, <<"buy_cargo">>) =>
                      {refused, {call_error, 16#0F, unknown_error}}})).

at_lisbon() ->
    answering(#{voyage() => {ok, #{<<"state">>     => <<"made_landfall">>,
                                   <<"bound_for">> => ?LISBON,
                                   <<"moored">>    => true}},
                ship_at(?MACAO) => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"moored">>,
                                           <<"ship">>  => hull(2, #{?PEPPER => 40.0})}},
                at(?LISBON, <<"sell_cargo">>) =>
                    {ok, #{<<"discharged">> => 40.0, <<"coin">> => 900.0,
                           <<"ship">> => hull(2, #{})}}}).

at_sea() ->
    answering(#{voyage() => {ok, #{<<"state">>     => <<"in_passage">>,
                                   <<"bound_for">> => ?LISBON,
                                   <<"sailed_at">> => 1786528800000,
                                   <<"due_at">>    => 1786528890000}}}).

silence() ->
    answering(#{}).

%% Everything answers except the one call that matters, which is the shape of a
%% harbour that took the order and then lost its link on the way back.
silent_on_buying() ->
    answering(maps:merge(macao(#{}),
                         #{at(?MACAO, <<"buy_cargo">>) => {unreachable, timeout}})).

replaying_the_receipt() ->
    answering(macao(#{})).

refusing_to_sell() ->
    answering(maps:merge(macao(#{}),
                         #{at(?MACAO, <<"sell_cargo">>) =>
                               {refused, {call_error, 16#0F, unknown_error}}})).

%% Macao, holding the ship with `Aboard' in her hold and willing to trade.
%% The quote scales with the quantity asked for, the way a real quay does,
%% because a fixed answer would make "the purse will not stretch" untestable.
macao(Aboard) ->
    #{voyage() => {ok, #{<<"state">> => <<"never_sailed">>}},
      ship_at(?MACAO) => {ok, #{<<"state">> => <<"moored">>,
                                <<"ship">>  => hull(0, Aboard)}},
      ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}},
      at(?MACAO, <<"quote_purchase">>) =>
          fun(Payload) ->
                  Tons = maps:get(<<"quantity">>, Payload),
                  {ok, #{<<"coin">>        => round2(?A_TON_OF_PEPPER * Tons),
                         <<"price_after">> => 16.18}}
          end,
      at(?MACAO, <<"buy_cargo">>) =>
          fun(Payload) ->
                  Tons = maps:get(<<"quantity">>, Payload),
                  {ok, #{<<"filled">> => Tons,
                         <<"coin">>   => round2(?A_TON_OF_PEPPER * Tons),
                         <<"ship">>   => hull(0, aboard(Aboard, Tons))}}
          end,
      at(?MACAO, <<"sail_ship">>) =>
          {ok, #{<<"ship">>         => ?SHIP,
                 <<"hop">>          => 1,
                 <<"bound_for">>    => ?LISBON,
                 <<"consigned_to">> => ?OCEAN}}}.

aboard(Aboard, Tons) ->
    Aboard#{?PEPPER => maps:get(?PEPPER, Aboard, 0.0) + Tons}.

answering(Script) ->
    tom_wire_fake:install(
      fun(Procedure, Payload) ->
              answer(maps:get(Procedure, Script, {unreachable, nobody_home}), Payload)
      end).

answer(Fun, Payload) when is_function(Fun, 1) -> Fun(Payload);
answer(Answer, _Payload)                      -> Answer.

voyage() -> at(?OCEAN, <<"get_voyage">>).

ship_at(Harbour) -> at(Harbour, <<"get_ship">>).

at(Target, Procedure) -> tom_names:procedure(Target, Procedure).

hull(Hop, Cargo) ->
    #{<<"ship">>      => ?SHIP,
      <<"owner">>     => ?HOUSE,
      <<"hold">>      => 200.0,
      <<"cargo">>     => Cargo,
      <<"hop">>       => Hop,
      <<"custodian">> => ?MACAO}.
