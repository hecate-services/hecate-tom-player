%% @doc The processes, running, rather than the functions inside them.
%%
%% Every other suite in this repository calls a function. This one starts the
%% gen_servers with short timers and a scripted mesh and waits for the house to
%% converge on its own, because a timer that is never armed and a cast that goes
%% to a name nobody registered are exactly the faults a function test cannot see.
-module(wiring_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SHIP, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(OCEAN, <<"mri:instance:io.macula/tom/ocean">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).
-define(PEPPER, <<"mri:class:io.macula/tom/good/pepper">>).

%% Short enough that a test does not sit around, long enough that a slow machine
%% does not fail on a scheduling hiccup.
-define(TICK_MS, 25).
-define(PATIENCE_MS, 5_000).

wiring_test_() ->
    {foreach, fun setup/0, fun teardown/1,
     [fun the_house_finds_its_ship_on_its_own/1,
      fun prices_arrive_without_being_asked/1,
      fun a_watcher_hears_about_every_change/1,
      fun a_mesh_that_will_not_subscribe_is_survivable/1,
      fun the_sweep_settles_what_a_crash_left_open/1]}.

%% Nobody pokes anything: the locate timer fires on its own and the picture
%% appears. This is the loop that makes a house independent of ever having
%% received a fact.
the_house_finds_its_ship_on_its_own(Config) ->
    {"the locate loop finds the ship with nobody poking it",
     fun() ->
        at_macao(),
        {ok, _} = keep_house:start_link(Config),
        {ok, _} = find_ship:start_link(Config),
        ok = until(fun() ->
                           maps:get(standing, tom_house:sight(keep_house:house()))
                               =:= moored
                   end),
        ?assertMatch(#{where := ?MACAO}, tom_house:sight(keep_house:house()))
     end}.

prices_arrive_without_being_asked(Config) ->
    {"the quote loop fills the market in without being asked",
     fun() ->
        at_macao(),
        {ok, _} = keep_house:start_link(Config),
        {ok, _} = read_quotes:start_link(Config),
        ok = until(fun() -> quoted(?MACAO) =/= [] end),
        ?assertMatch([#{<<"good">> := ?PEPPER}], quoted(?MACAO))
     end}.

%% This is the path the page's live update runs on. A watcher that stops hearing
%% is a page that quietly stops being true.
a_watcher_hears_about_every_change(Config) ->
    {"a watcher is sent the whole board on every change",
     fun() ->
        at_macao(),
        {ok, _} = keep_house:start_link(Config),
        ok = keep_house:watch(self()),
        ok = keep_house:note_trouble(nothing_much, a_reason),
        receive
            {house_changed, View} ->
                ?assert(is_map(View)),
                ?assert(maps:is_key(purse, View))
        after ?PATIENCE_MS ->
                error(the_watcher_heard_nothing)
        end
     end}.

%% The mesh takes a few seconds to attach at boot, so a subscription that will
%% not bind yet has to be a retry rather than a crash. The fake never binds at
%% all, which is the worst version of the same thing.
a_mesh_that_will_not_subscribe_is_survivable(Config) ->
    {"a subscription that never binds keeps retrying instead of dying",
     fun() ->
        at_macao(),
        {ok, _} = keep_house:start_link(Config),
        {ok, Watcher} = watch_ports:start_link(Config),
        timer:sleep(3 * ?TICK_MS),
        ?assert(is_process_alive(Watcher))
     end}.

%% The sweep's timer, doing at boot what a person would otherwise have to
%% remember to do.
the_sweep_settles_what_a_crash_left_open(Config) ->
    {"the sweep timer settles an order left open by a crash",
     fun() ->
        %% A ledger with an order in it and no conclusion, exactly as a crash
        %% between the write and the answer leaves one.
        {ok, Ledger, []} = tom_ledger:open(maps:get(ledger, Config)),
        ok = tom_ledger:append(Ledger, {house_opened_v1,
                                        #{purse => 1000.0, ship => ?SHIP, at => 1}}),
        ok = tom_ledger:append(Ledger, {purchase_ordered_v1,
                                        #{order => <<"left-open">>, harbour => ?MACAO,
                                          good => ?PEPPER, quantity => 40.0, at => 2}}),
        ok = tom_ledger:close(Ledger),

        at_macao(),
        {ok, _} = keep_house:start_link(Config),
        ?assertMatch([#{order := <<"left-open">>}],
                     tom_house:unsettled(keep_house:house())),
        {ok, _} = settle_orders:start_link(Config),
        ok = until(fun() -> tom_house:unsettled(keep_house:house()) =:= [] end),
        ?assertEqual(418.58, round2(tom_house:purse(keep_house:house()))),
        ?assertMatch([#{<<"order">> := <<"left-open">>}],
                     tom_wire_fake:calls_to(<<"buy_cargo">>))
     end}.

%%% Fixtures

setup() ->
    #{names              => names(),
      ledger             => a_path(),
      purse              => 1000.0,
      quote_interval_ms  => ?TICK_MS,
      locate_interval_ms => ?TICK_MS}.

teardown(_Config) ->
    tom_wire_fake:forget(),
    _ = [stopped(erlang:whereis(Name))
         || Name <- [settle_orders, find_ship, read_quotes, watch_ports, keep_house]],
    ok.

stopped(undefined) ->
    ok;
stopped(Pid) ->
    try gen_server:stop(Pid)
    catch exit:noproc -> ok
    end.

%% Poll rather than sleep a fixed time: a fast machine finishes at once and a
%% loaded one still gets its answer.
until(Done) -> waited(Done(), Done, ?PATIENCE_MS).

waited(true, _Done, _Left)             -> ok;
waited(false, _Done, Left) when Left =< 0 -> error(never_happened);
waited(false, Done, Left) ->
    timer:sleep(10),
    waited(Done(), Done, Left - 10).

quoted(Harbour) ->
    Quotes = maps:get(quotes, keep_house:snapshot()),
    maps:get(quotes, maps:get(Harbour, Quotes, #{}), []).

round2(F) -> round(F * 100) / 100.

at_macao() ->
    tom_wire_fake:install(
      fun(Procedure, Payload) ->
              answer(maps:get(Procedure, macao(), {unreachable, nobody_home}), Payload)
      end).

answer(Fun, Payload) when is_function(Fun, 1) -> Fun(Payload);
answer(Answer, _Payload)                      -> Answer.

macao() ->
    #{at(?OCEAN, <<"get_voyage">>) => {ok, #{<<"state">> => <<"never_sailed">>}},
      at(?MACAO, <<"get_ship">>) => {ok, #{<<"state">> => <<"moored">>,
                                           <<"ship">>  => hull()}},
      at(?LISBON, <<"get_ship">>) => {ok, #{<<"state">> => <<"not_here">>}},
      at(?MACAO, <<"list_quotes">>) =>
          {ok, #{<<"harbour">> => ?MACAO,
                 <<"at">>      => 1786528800000,
                 <<"quotes">>  => [#{<<"good">>  => ?PEPPER,
                                     <<"price">> => 12.915496650148841,
                                     <<"stock">> => 43.918}]}},
      at(?LISBON, <<"list_quotes">>) =>
          {ok, #{<<"harbour">> => ?LISBON, <<"at">> => 1786528800000,
                 <<"quotes">> => []}},
      at(?MACAO, <<"buy_cargo">>) =>
          {ok, #{<<"filled">> => 40.0, <<"coin">> => 581.42, <<"ship">> => hull()}}}.

at(Target, Procedure) -> tom_names:procedure(Target, Procedure).

hull() ->
    #{<<"ship">> => ?SHIP, <<"hold">> => 200.0, <<"cargo">> => #{},
      <<"hop">> => 0, <<"custodian">> => ?MACAO}.

names() ->
    {ok, Names} = tom_names:read(#{realm_name => <<"io.macula">>,
                                   player     => <<"raf">>,
                                   ship       => <<"santa_clara">>,
                                   harbours   => [<<"macao">>, <<"lisbon">>],
                                   goods      => [<<"pepper">>]}),
    Names.

a_path() ->
    Unique = erlang:phash2({erlang:system_time(nanosecond),
                            erlang:unique_integer([positive])}),
    filename:join([os:getenv("TMPDIR", "/tmp"),
                   "hecate_tom_player_test",
                   integer_to_list(Unique),
                   "house.log"]).
