%% @doc One pass of asking, against a scripted mesh.
%%
%% Every clause here is a state the world can genuinely be in, including the
%% three that look like contradictions and are not: a hull at sea that a port
%% still answers for, two ports both claiming one hull, and a hull nobody is
%% holding that is nonetheless not lost.
-module(find_ship_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SHIP, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).
-define(PEPPER, <<"mri:class:io.macula/tom/good/pepper">>).

%% AT SEA, AND MACAO STILL ANSWERS FOR HER. This is the whole of what the ocean
%% dissolving changed here: custody does not move until Lisbon says held, so the
%% port she sailed from knows where she is and when she is due.
at_sea_the_port_she_sailed_from_answers_test() ->
    answering(#{ship_at(?MACAO) => {ok, #{<<"state">>     => <<"in_passage">>,
                                          <<"ship">>      => hull(5, #{}),
                                          <<"bound_for">> => ?LISBON,
                                          <<"sailed_at">> => 1786528800000,
                                          <<"due_at">>    => 1786528890000}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := in_passage, bound_for := ?LISBON,
                   due_at := 1786528890000}, Sight).

alongside_at_the_port_that_holds_her_test() ->
    answering(#{ship_at(?MACAO) => {ok, #{<<"state">> => <<"moored">>,
                                          <<"ship">>  => hull(0, #{})}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := moored, where := ?MACAO}, Sight).

%% The answer a house gets on the way back up after being shut down for a whole
%% passage. Nothing was replayed at it and nothing was queued for it.
home_after_a_voyage_test() ->
    answering(#{ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"moored">>,
                                           <<"ship">>  => hull(6, #{?PEPPER => 40.0})}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := moored, where := ?LISBON}, Sight),
    ?assertEqual(#{?PEPPER => 40.0}, maps:get(<<"cargo">>, maps:get(hull, Sight))).

%% SHE ARRIVED AND THE DESTINATION IS DARK. Macao goes on answering in_passage
%% while it knocks, which is the truth: nobody else has taken her. The old ocean
%% called this made_landfall and it was a state only a third party could see.
overdue_because_the_far_port_is_dark_test() ->
    answering(#{ship_at(?MACAO) => {ok, #{<<"state">>     => <<"in_passage">>,
                                          <<"ship">>      => hull(5, #{}),
                                          <<"bound_for">> => ?LISBON,
                                          <<"due_at">>    => 1786528890000}},
                ship_at(?LISBON) => {unreachable, timeout}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := in_passage, bound_for := ?LISBON}, Sight).

%% THE ONE INFERENCE. Every port answered, none has her, and this house knows she
%% sailed and was due. Nobody is left to ask, so the house concludes.
lost_at_sea_test() ->
    answering(#{ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    {sight, Sight} = find_ship:look_around(names(), was_sailing(-1)),
    ?assertMatch(#{standing := was_lost, bound_for := ?LISBON}, Sight).

%% AND SHE IS NOT LOST MERELY BECAUSE NOBODY HAS HER. A hull whose hour has not
%% come is between two ports and that is not news, so the picture is left alone.
not_yet_due_is_not_lost_test() ->
    answering(#{ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    ?assertMatch({no_news, she_is_at_sea_and_not_yet_due},
                 find_ship:look_around(names(), was_sailing(3_600_000))).

%% THE CUSTODY RULE. Two ports claiming one hull is resolved by the hop and by
%% nothing else: no vote, no quorum, and no comparison of two machines' clocks.
the_higher_hop_wins_test() ->
    answering(#{ship_at(?MACAO)  => {ok, #{<<"state">> => <<"moored">>,
                                           <<"ship">>  => hull(4, #{})}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"moored">>,
                                           <<"ship">>  => hull(6, #{})}}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{where := ?LISBON}, Sight).

%% One port being down does not stop another answering for a hull it is holding.
a_silent_port_does_not_hide_a_moored_ship_test() ->
    answering(#{ship_at(?MACAO) => {ok, #{<<"state">> => <<"moored">>,
                                          <<"ship">>  => hull(2, #{})}},
                ship_at(?LISBON) => {unreachable, timeout}}),
    {sight, Sight} = find_ship:look_around(names()),
    ?assertMatch(#{standing := moored, where := ?MACAO}, Sight).

%% SILENCE IS NOT not_here. Nobody answered, so the house claims nothing and the
%% last picture stays on the page with its age on it. Concluding "lost" from a
%% flaky link is the expensive version of this mistake.
when_nobody_answers_nothing_is_claimed_test() ->
    answering(#{}),
    ?assertMatch({no_news, nobody_answered}, find_ship:look_around(names())),
    ?assertMatch({no_news, nobody_answered},
                 find_ship:look_around(names(), was_sailing(-1))).

%% A hull no port is holding, that this house has never seen sail, does not exist
%% yet. Saying so beats an empty page.
never_sailed_and_nobody_holds_her_test() ->
    answering(#{ship_at(?MACAO)  => {ok, #{<<"state">> => <<"not_here">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    ?assertMatch({sight, #{standing := never_sailed}}, find_ship:look_around(names())).

%% A port growing a state this house has never heard of is news, not a picture.
%% Guessing would be worse than saying so, and concluding she sank would be worse
%% than either.
an_unrecognised_state_is_not_a_picture_test() ->
    answering(#{ship_at(?MACAO)  => {ok, #{<<"state">> => <<"becalmed">>}},
                ship_at(?LISBON) => {ok, #{<<"state">> => <<"not_here">>}}}),
    ?assertMatch({no_news, {a_port_said_something_new, _}},
                 find_ship:look_around(names(), was_sailing(-1))).

%%% Fixtures

answering(Script) ->
    tom_wire_fake:install(
      fun(Procedure, _Payload) ->
              maps:get(Procedure, Script, {unreachable, nobody_home})
      end).

%% What this house last believed: at sea, due Ms from now. A negative Ms is a
%% ship whose hour came and went.
was_sailing(Ms) ->
    #{standing  => in_passage,
      where     => ?MACAO,
      bound_for => ?LISBON,
      sailed_at => erlang:system_time(millisecond) - 90_000,
      due_at    => erlang:system_time(millisecond) + Ms,
      cause     => undefined}.

names() ->
    {ok, Names} = tom_names:read(#{realm_name => <<"io.macula">>,
                                   player     => <<"raf">>,
                                   ship       => <<"santa_clara">>,
                                   harbours   => [<<"macao">>, <<"lisbon">>],
                                   goods      => [<<"pepper">>]}),
    Names.

ship_at(Harbour) -> tom_names:procedure(Harbour, <<"get_ship">>).

hull(Hop, Cargo) ->
    #{<<"ship">>      => ?SHIP,
      <<"owner">>     => <<"mri:instance:io.macula/tom/house/raf">>,
      <<"hold">>      => 200.0,
      <<"cargo">>     => Cargo,
      <<"hop">>       => Hop,
      <<"custodian">> => ?MACAO}.
