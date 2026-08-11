%% @doc The aggregate: a fold of things that happened.
%%
%% The idempotence tests are the important ones here. The reliability pattern
%% re-calls an outstanding order after a crash, and a second settlement of one
%% order has to be worth nothing. If it is worth a second subtraction the whole
%% design is unsafe, and the failure is silent and looks like a player who was
%% robbed.
-module(tom_house_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SHIP, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).
-define(PEPPER, <<"mri:class:io.macula/tom/good/pepper">>).

an_empty_house_has_nothing_test() ->
    H = tom_house:empty(),
    ?assertEqual(0.0, tom_house:purse(H)),
    ?assertNot(tom_house:opened(H)),
    ?assertEqual(#{}, tom_house:cargo(H)),
    ?assertMatch(#{standing := unknown}, tom_house:sight(H)).

opening_sets_the_purse_once_test() ->
    H = tom_house:replay([opened(1000.0), opened(9999.0)], tom_house:empty()),
    ?assertEqual(1000.0, tom_house:purse(H)),
    ?assert(tom_house:opened(H)).

a_purchase_takes_money_out_test() ->
    H = tom_house:replay([opened(1000.0),
                          ordered(<<"a">>, ?MACAO, 40.0),
                          settled(<<"a">>, 581.42, 40.0)],
                         tom_house:empty()),
    ?assertEqual(418.58, round2(tom_house:purse(H))),
    ?assertEqual([], tom_house:unsettled(H)).

a_sale_puts_money_in_test() ->
    H = tom_house:replay([opened(1000.0),
                          {sale_ordered_v1, #{order => <<"s">>, harbour => ?LISBON,
                                              good => ?PEPPER, quantity => 40.0,
                                              at => 3}},
                          {sale_settled_v1, #{order => <<"s">>, coin => 900.0,
                                              discharged => 40.0, at => 4}}],
                         tom_house:empty()),
    ?assertEqual(1900.0, tom_house:purse(H)).

%% THE ONE THAT MATTERS. A retry after a crash replays the harbour's receipt,
%% so the same settlement arrives twice and must be worth one subtraction.
settling_twice_moves_the_purse_once_test() ->
    Facts = [opened(1000.0), ordered(<<"a">>, ?MACAO, 40.0),
             settled(<<"a">>, 581.42, 40.0), settled(<<"a">>, 581.42, 40.0)],
    H = tom_house:replay(Facts, tom_house:empty()),
    ?assertEqual(418.58, round2(tom_house:purse(H))).

%% Two calls with one key are one order, whichever of them lands first.
ordering_twice_under_one_key_is_one_order_test() ->
    H = tom_house:replay([opened(1000.0),
                          ordered(<<"a">>, ?MACAO, 40.0),
                          ordered(<<"a">>, ?LISBON, 999.0)],
                         tom_house:empty()),
    ?assertEqual(1, length(tom_house:orders(H))),
    ?assertMatch([#{harbour := ?MACAO, quantity := 40.0}], tom_house:orders(H)).

a_settlement_for_an_order_never_placed_does_nothing_test() ->
    H = tom_house:replay([opened(1000.0), settled(<<"ghost">>, 581.42, 40.0)],
                         tom_house:empty()),
    ?assertEqual(1000.0, tom_house:purse(H)).

a_refusal_closes_an_order_without_touching_the_purse_test() ->
    H = tom_house:replay([opened(1000.0), ordered(<<"a">>, ?MACAO, 40.0),
                          {purchase_refused_v1, #{order => <<"a">>,
                                                  reason => <<"quay_empty">>,
                                                  at => 4}}],
                         tom_house:empty()),
    ?assertEqual(1000.0, tom_house:purse(H)),
    ?assertEqual([], tom_house:unsettled(H)),
    ?assertMatch([#{state := refused}], tom_house:orders(H)).

%% A settlement arriving after a refusal is the harbour changing its mind, which
%% it cannot do. The first conclusion stands.
a_settlement_after_a_refusal_does_nothing_test() ->
    H = tom_house:replay([opened(1000.0), ordered(<<"a">>, ?MACAO, 40.0),
                          {purchase_refused_v1, #{order => <<"a">>,
                                                  reason => <<"quay_empty">>, at => 4}},
                          settled(<<"a">>, 581.42, 40.0)],
                         tom_house:empty()),
    ?assertEqual(1000.0, tom_house:purse(H)).

an_open_order_is_what_a_boot_resumes_from_test() ->
    H = tom_house:replay([opened(1000.0), ordered(<<"a">>, ?MACAO, 40.0),
                          ordered(<<"b">>, ?MACAO, 5.0),
                          settled(<<"b">>, 60.0, 5.0)],
                         tom_house:empty()),
    ?assertMatch([#{order := <<"a">>}], tom_house:unsettled(H)).

the_hold_comes_from_the_custodian_test() ->
    H = tom_house:replay([opened(1000.0), sighted(moored, ?MACAO, hull(6, #{?PEPPER => 40.0}))],
                         tom_house:empty()),
    ?assertEqual(#{?PEPPER => 40.0}, tom_house:cargo(H)),
    ?assertEqual(200.0, tom_house:hold(H)),
    ?assertEqual(160.0, tom_house:free_hold(H)).

%% Hop is the custody counter and only a durable acceptance advances it, so it
%% orders two sightings without comparing two machines' clocks.
a_sighting_at_a_lower_hop_is_older_news_test() ->
    H = tom_house:replay([opened(1000.0),
                          sighted(moored, ?LISBON, hull(6, #{?PEPPER => 40.0})),
                          sighted(moored, ?MACAO, hull(4, #{}))],
                         tom_house:empty()),
    ?assertMatch(#{where := ?LISBON}, tom_house:sight(H)),
    ?assertEqual(#{?PEPPER => 40.0}, tom_house:cargo(H)).

%% Mooring and consignment happen at the SAME hop, because a consignment is not
%% a hop. An equal hop therefore has to be allowed through or the picture freezes
%% at "alongside" for a ship that has been committed to a voyage.
an_equal_hop_still_changes_the_picture_test() ->
    H = tom_house:replay([opened(1000.0),
                          sighted(moored, ?MACAO, hull(6, #{})),
                          sighted(consigned, ?MACAO, hull(6, #{}))],
                         tom_house:empty()),
    ?assertMatch(#{standing := consigned}, tom_house:sight(H)).

%% At sea the ocean answers with no ship map, because it cannot see cargo. The
%% picture of the hold must survive that, or a player watching a voyage sees
%% their cargo vanish and come back.
a_sighting_without_a_hull_keeps_the_hold_test() ->
    H = tom_house:replay([opened(1000.0),
                          sighted(moored, ?MACAO, hull(6, #{?PEPPER => 40.0})),
                          {ship_sighted_v1, #{standing => in_passage,
                                              bound_for => ?LISBON,
                                              due_at => 1786528890000, at => 20}}],
                         tom_house:empty()),
    ?assertMatch(#{standing := in_passage, due_at := 1786528890000},
                 tom_house:sight(H)),
    ?assertEqual(#{?PEPPER => 40.0}, tom_house:cargo(H)).

an_unknown_fact_changes_nothing_test() ->
    H0 = tom_house:replay([opened(1000.0)], tom_house:empty()),
    ?assertEqual(H0, tom_house:apply_fact({some_fact_from_the_future_v9, #{}}, H0)).

%% WHAT WAS ASKED FOR IS NOT WHAT MOVED, and the two are visibly different in
%% normal play rather than in some edge case: a quay holds what it holds, so an
%% order for five tons at a shallow port fills two and a half and the receipt
%% says so. `quantity' stays the ordered amount because a retry re-sends it
%% under the same key; `moved/1' is what a player is shown, and showing the
%% ordered amount instead is a page telling somebody they sold twice what they
%% sold.
an_order_shows_what_moved_not_what_was_asked_test() ->
    H = tom_house:replay([opened(1000.0),
                          ordered(<<"a">>, ?MACAO, 5.0),
                          settled(<<"a">>, 209.38, 2.4551)],
                         tom_house:empty()),
    {ok, Order} = tom_house:order(H, <<"a">>),
    ?assertEqual(5.0, maps:get(quantity, Order)),
    ?assertEqual(2.4551, tom_house:moved(Order)).

%% An order still in flight has moved nothing yet, so what it asked for is the
%% only number there is and it is the honest one to show.
an_order_still_in_flight_shows_what_it_asked_for_test() ->
    H = tom_house:replay([opened(1000.0), ordered(<<"a">>, ?MACAO, 5.0)],
                         tom_house:empty()),
    {ok, Order} = tom_house:order(H, <<"a">>),
    ?assertEqual(5.0, tom_house:moved(Order)).

%%% Fixtures

opened(Purse) ->
    {house_opened_v1, #{purse => Purse, ship => ?SHIP, at => 1}}.

ordered(Key, Harbour, Quantity) ->
    {purchase_ordered_v1, #{order => Key, harbour => Harbour, good => ?PEPPER,
                            quantity => Quantity, at => 2}}.

settled(Key, Coin, Filled) ->
    {purchase_settled_v1, #{order => Key, coin => Coin, filled => Filled, at => 3}}.

sighted(Standing, Where, Hull) ->
    {ship_sighted_v1, #{standing => Standing, where => Where, hull => Hull, at => 10}}.

hull(Hop, Cargo) ->
    #{<<"ship">> => ?SHIP, <<"hold">> => 200.0, <<"cargo">> => Cargo,
      <<"hop">> => Hop, <<"custodian">> => ?MACAO}.

round2(F) -> round(F * 100) / 100.
