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

%% Mooring and sailing happen at the SAME hop, because leaving is not a hop: the
%% hop advances when the far port takes her. An equal hop therefore has to be
%% allowed through or the picture freezes at "alongside" for a ship that is
%% already at sea.
an_equal_hop_still_changes_the_picture_test() ->
    H = tom_house:replay([opened(1000.0),
                          sighted(moored, ?MACAO, hull(6, #{})),
                          sighted(in_passage, ?MACAO, hull(6, #{}))],
                         tom_house:empty()),
    ?assertMatch(#{standing := in_passage}, tom_house:sight(H)).

%% At sea a sight can arrive with no ship map on it. The
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

%% A ship on the bottom has no hold. The was_lost sight carries no hull key, so
%% before the aggregate enforced this the old hull survived the default in
%% sighted/2, was written to the ledger and replayed for ever, and the player was
%% left looking at a manifest for cargo on the sea floor.
a_wreck_takes_her_cargo_down_with_her_test() ->
    H = tom_house:replay([opened(1000.0),
                          sighted(moored, ?MACAO, hull(6, #{?PEPPER => 40.0})),
                          {ship_sighted_v1, #{standing => was_lost,
                                              bound_for => ?LISBON,
                                              cause => storm, at => 20}}],
                         tom_house:empty()),
    ?assertMatch(#{standing := was_lost, cause := storm}, tom_house:sight(H)),
    ?assertEqual(#{}, tom_house:cargo(H)).

%% And it survives a replay, because the ledger is what the house wakes up to.
a_wreck_stays_empty_across_a_replay_test() ->
    Facts = [opened(1000.0),
             sighted(moored, ?MACAO, hull(6, #{?PEPPER => 40.0})),
             {ship_sighted_v1, #{standing => was_lost, bound_for => ?LISBON,
                                 cause => storm, at => 20}}],
    ?assertEqual(#{}, tom_house:cargo(tom_house:replay(Facts, tom_house:empty()))).

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

%%% The cash book

a_house_that_has_done_nothing_has_an_empty_book_test() ->
    Book = tom_house:cash_book(tom_house:empty()),
    ?assertEqual(0.0, maps:get(opened_with, Book)),
    ?assertEqual([], maps:get(entries, Book)),
    ?assertEqual(0.0, maps:get(closing, Book)).

the_book_opens_with_what_the_house_opened_with_test() ->
    Book = tom_house:cash_book(tom_house:replay([opened(1000.0)], tom_house:empty())),
    ?assertEqual(1000.0, maps:get(opened_with, Book)),
    ?assertEqual(1000.0, maps:get(closing, Book)).

%% THE POINT OF THE WHOLE THING. The closing balance is reached by adding up
%% from what the house opened with; the purse is reached by moving one number on
%% every settlement. Two routes, one answer. A book that took its closing balance
%% from the purse could never have told us that, and would be decoration.
the_book_closes_where_the_purse_stands_test() ->
    H = trading_house(),
    ?assertEqual(round2(tom_house:purse(H)),
                 round2(maps:get(closing, tom_house:cash_book(H)))).

a_purchase_is_money_out_and_a_sale_is_money_in_test() ->
    [Out, In] = maps:get(entries, tom_house:cash_book(trading_house())),
    ?assertMatch(#{kind := purchase, coin := 581.42, harbour := ?MACAO}, Out),
    ?assertMatch(#{kind := sale, coin := 900.0, harbour := ?LISBON}, In),
    ?assertEqual(418.58, round2(maps:get(balance, Out))),
    ?assertEqual(1318.58, round2(maps:get(balance, In))).

%% Money moves when a port settles, not when an order is placed. An order sent
%% first can settle second, so the book is in settlement order and the orders
%% table is not.
the_book_is_in_the_order_the_money_moved_test() ->
    H = tom_house:replay([opened(1000.0),
                          bought(<<"slow">>, 10.0, 2), bought(<<"quick">>, 10.0, 3),
                          paid(<<"quick">>, 100.0, 4), paid(<<"slow">>, 200.0, 9)],
                         tom_house:empty()),
    ?assertMatch([#{order := <<"quick">>}, #{order := <<"slow">>}],
                 maps:get(entries, tom_house:cash_book(H))).

%% A refusal cost nothing and an order still open has committed nothing. Both
%% belong in the orders table, where a player looks for what became of an order,
%% and neither belongs in an account of what became of the money.
nothing_that_did_not_move_money_is_in_the_book_test() ->
    H = tom_house:replay([opened(1000.0),
                          bought(<<"a">>, 10.0, 2), bought(<<"b">>, 10.0, 3),
                          {purchase_refused_v1, #{order => <<"a">>, at => 4,
                                                  reason => <<"quay_empty">>}}],
                         tom_house:empty()),
    ?assertEqual(2, length(tom_house:orders(H))),
    ?assertEqual([], maps:get(entries, tom_house:cash_book(H))),
    ?assertEqual(1000.0, maps:get(closing, tom_house:cash_book(H))).

%% The reliability pattern re-calls an outstanding order after a crash, so one
%% settlement arrives twice. It is worth one line in the book for the same reason
%% it is worth one subtraction from the purse.
settling_twice_is_one_line_in_the_book_test() ->
    H = tom_house:replay([opened(1000.0), bought(<<"a">>, 10.0, 2),
                          paid(<<"a">>, 581.42, 3), paid(<<"a">>, 581.42, 3)],
                         tom_house:empty()),
    ?assertEqual(1, length(maps:get(entries, tom_house:cash_book(H)))),
    ?assertEqual(418.58, round2(maps:get(closing, tom_house:cash_book(H)))).

%% A quay holds what it holds, so the tons in the book are the tons that moved
%% rather than the tons that were asked for.
the_book_carries_the_tons_that_moved_test() ->
    H = tom_house:replay([opened(1000.0), bought(<<"a">>, 5.0, 2),
                          paid_for(<<"a">>, 209.38, 2.4551, 3)],
                         tom_house:empty()),
    ?assertMatch([#{tons := 2.4551}], maps:get(entries, tom_house:cash_book(H))).

%%% Fixtures

%% Bought at Macao, sold at Lisbon, and 1000 - 581.42 + 900 to show for it.
trading_house() ->
    tom_house:replay([opened(1000.0),
                      bought(<<"buy">>, 40.0, 2), paid(<<"buy">>, 581.42, 3),
                      offered(<<"sell">>, 40.0, 4), earned(<<"sell">>, 900.0, 5)],
                     tom_house:empty()).

bought(Key, Tons, At) ->
    {purchase_ordered_v1, #{order => Key, harbour => ?MACAO, good => ?PEPPER,
                            quantity => Tons, at => At}}.

paid(Key, Coin, At) -> paid_for(Key, Coin, 40.0, At).

paid_for(Key, Coin, Filled, At) ->
    {purchase_settled_v1, #{order => Key, coin => Coin, filled => Filled, at => At}}.

offered(Key, Tons, At) ->
    {sale_ordered_v1, #{order => Key, harbour => ?LISBON, good => ?PEPPER,
                        quantity => Tons, at => At}}.

earned(Key, Coin, At) ->
    {sale_settled_v1, #{order => Key, coin => Coin, discharged => 40.0, at => At}}.

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
