%% @doc One pass of asking, against a scripted mesh.
%%
%% Every clause here is a state the world can genuinely be in, including the two
%% that look like contradictions and are not: a landfall the destination has not
%% confirmed, and two ports both claiming the same hull.
-module(find_ship_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SHIP, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(OCEAN, <<"mri:instance:io.macula/tom/ocean">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).
-define(PEPPER, <<"mri:class:io.macula/tom/good/pepper">>).

%% At sea the ocean is the custodian, so no port is asked at all.
at_sea_nobody_asks_a_port_test() ->
    answering(#{voyage() => {ok, #{<<"state">>     => <<"in_passage">>,
                                   <<"ship">>      => ?SHIP,
                                   <<"from">>      => ?MACAO,
                                   <<"bound_for">> => ?LISBON,
                                   <<"sailed_at">> => 1786528800000,
                                   <<"due_at">>    => 1786528890000}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := in_passage, where := ?OCEAN, bound_for := ?LISBON,
                   due_at := 1786528890000}, Sight),
    ?assertEqual([], tom_wire_fake:calls_to(<<"get_ship">>)).

alongside_at_the_port_that_holds_her_test() ->
    answering(#{voyage() => {ok, #{<<"state">> => <<"never_sailed">>}},
                ship_at(?MACAO) => {ok, #{<<"state">> => <<"moored">>,
                                          <<"ship">>  => hull(0, #{})}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := moored, where := ?MACAO}, Sight).

%% The voyage is over and the destination has custody. This is the answer a
%% house gets on the way back up after being shut down for a whole passage.
home_after_a_voyage_test() ->
    answering(#{voyage() => {ok, #{<<"state">>     => <<"made_landfall">>,
                                   <<"bound_for">> => ?LISBON,
                                   <<"moored">>    => true}},
                ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"moored">>,
                                           <<"ship">>  => hull(6, #{?PEPPER => 40.0})}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := moored, where := ?LISBON}, Sight),
    ?assertEqual(#{?PEPPER => 40.0}, maps:get(<<"cargo">>, maps:get(hull, Sight))).

%% Landfall is true from the moment the ocean writes it, even while the
%% destination is down and the knocking goes on. Reporting that gap is honest.
landfall_the_destination_has_not_confirmed_test() ->
    answering(#{voyage() => {ok, #{<<"state">>     => <<"made_landfall">>,
                                   <<"bound_for">> => ?LISBON,
                                   <<"moored">>    => false}},
                ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {unreachable, timeout}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := made_landfall, where := ?OCEAN, bound_for := ?LISBON},
                 Sight).

lost_at_sea_test() ->
    answering(#{voyage() => {ok, #{<<"state">>     => <<"was_lost">>,
                                   <<"bound_for">> => ?LISBON,
                                   <<"sailed_at">> => 1786528800000,
                                   <<"lost_at">>   => 1786528890000,
                                   <<"cause">>     => <<"pirates">>}},
                ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := was_lost, cause := <<"pirates">>, bound_for := ?LISBON},
                 Sight).

%% THE CUSTODY RULE. Two ports claiming one hull is resolved by the hop and by
%% nothing else: no vote, no quorum, and no comparison of two machines' clocks.
the_higher_hop_wins_test() ->
    answering(#{voyage() => {ok, #{<<"state">> => <<"made_landfall">>,
                                   <<"bound_for">> => ?LISBON}},
                ship_at(?MACAO)  => {ok, #{<<"state">> => <<"moored">>,
                                           <<"ship">>  => hull(4, #{})}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"moored">>,
                                           <<"ship">>  => hull(6, #{})}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{where := ?LISBON}, Sight).

%% A consignment is not a hop. The port still has her and says so.
consigned_and_still_at_the_port_test() ->
    answering(#{voyage() => {ok, #{<<"state">> => <<"never_sailed">>}},
                ship_at(?MACAO) => {ok, #{<<"state">>     => <<"consigned">>,
                                          <<"ship">>      => hull(4, #{}),
                                          <<"bound_for">> => ?LISBON}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := consigned, where := ?MACAO, bound_for := ?LISBON},
                 Sight).

%% The ocean being down does not stop a port answering for a hull it is holding.
a_silent_ocean_does_not_hide_a_moored_ship_test() ->
    answering(#{voyage() => {unreachable, timeout},
                ship_at(?MACAO) => {ok, #{<<"state">> => <<"moored">>,
                                          <<"ship">>  => hull(2, #{})}},
                ship_at(?LISBON) => {unreachable, timeout}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := moored, where := ?MACAO}, Sight).

%% Nobody answered, so the house says nothing rather than inventing a picture.
%% The last known one stays on the page with its age on it.
when_nobody_answers_nothing_is_claimed_test() ->
    answering(#{}),
    ?assertMatch({no_news, _}, find_ship:look_around(names())).

%% A hull that no port is holding and that the ocean has never seen does not
%% exist yet. Saying so beats an empty page.
never_sailed_and_nobody_holds_her_test() ->
    answering(#{voyage() => {ok, #{<<"state">> => <<"never_sailed">>}},
                ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    ?assertMatch({sight, #{standing := never_sailed}}, find_ship:look_around(names())).

%% The ocean growing a state this house has never heard of is news, not a
%% picture. Guessing would be worse than saying so.
an_unrecognised_state_is_not_a_picture_test() ->
    answering(#{voyage() => {ok, #{<<"state">> => <<"becalmed">>}},
                ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    ?assertMatch({no_news, {ocean_said_something_new, _}},
                 find_ship:look_around(names())).

%%% Fixtures

answering(Script) ->
    tom_wire_fake:install(
      fun(Procedure, _Payload) ->
              maps:get(Procedure, Script, {unreachable, nobody_home})
      end).

names() ->
    {ok, Names} = tom_names:read(#{realm_name => <<"io.macula">>,
                                   player     => <<"raf">>,
                                   ship       => <<"santa_clara">>,
                                   harbours   => [<<"macao">>, <<"lisbon">>],
                                   goods      => [<<"pepper">>]}),
    Names.

voyage() -> tom_names:procedure(?OCEAN, <<"get_voyage">>).

ship_at(Harbour) -> tom_names:procedure(Harbour, <<"get_ship">>).

hull(Hop, Cargo) ->
    #{<<"ship">>      => ?SHIP,
      <<"owner">>     => <<"mri:instance:io.macula/tom/house/raf">>,
      <<"hold">>      => 200.0,
      <<"cargo">>     => Cargo,
      <<"hop">>       => Hop,
      <<"custodian">> => ?MACAO}.
