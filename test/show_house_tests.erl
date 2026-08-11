%% @doc The page. If this is unusable the whole build has failed, whatever the
%% rest of the tests say.
%%
%% Two things are worth holding here. First, that every state the world can be in
%% renders into a sentence a person can act on, including the awkward ones.
%% Second, that nothing arriving off the mesh can put markup on the page: a
%% harbour is another player's process on another player's laptop, and its
%% payloads are somebody else's bytes.
-module(show_house_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SHIP, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(HOUSE, <<"mri:instance:io.macula/tom/house/raf">>).
-define(OCEAN, <<"mri:instance:io.macula/tom/ocean">>).
-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(LISBON, <<"mri:instance:io.macula/tom/harbour/lisbon">>).
-define(PEPPER, <<"mri:class:io.macula/tom/good/pepper">>).

%%% The page

the_page_carries_the_controls_test() ->
    Page = flat(show_house_page:page(moored_view())),
    ?assert(contains(Page, <<"<!doctype html>">>)),
    ?assert(contains(Page, <<"santa_clara">>)),
    %% Buying, selling, sailing and pricing, all reachable without reading a
    %% manual.
    ?assert(contains(Page, <<"value=\"buy\"">>)),
    ?assert(contains(Page, <<"value=\"sell\"">>)),
    ?assert(contains(Page, <<"value=\"sail\"">>)),
    ?assert(contains(Page, <<"value=\"quote\"">>)),
    %% And it keeps up on its own.
    ?assert(contains(Page, <<"EventSource('/stream')">>)).

%% The controls are OUTSIDE the swapped fragment, so an update arriving while
%% somebody is typing a quantity cannot eat what they typed.
the_board_does_not_carry_the_controls_test() ->
    Board = flat(show_house_page:board(moored_view())),
    ?assertNot(contains(Board, <<"value=\"buy\"">>)),
    ?assertNot(contains(Board, <<"<input">>)).

the_board_shows_the_purse_the_hold_and_both_ports_test() ->
    Board = flat(show_house_page:board(moored_view())),
    ?assert(contains(Board, <<"418.58">>)),
    ?assert(contains(Board, <<"alongside at macao">>)),
    ?assert(contains(Board, <<"pepper">>)),
    ?assert(contains(Board, <<"40">>)),
    ?assert(contains(Board, <<"macao price">>)),
    ?assert(contains(Board, <<"lisbon price">>)),
    ?assert(contains(Board, <<"12.9155">>)),
    %% A good the port did not quote is a dash, not a zero. A zero is a price.
    ?assert(contains(Board, <<"&mdash;">>)).

%% Every state the world can be in has a sentence, including the two that look
%% like contradictions.
each_standing_has_a_sentence_test() ->
    Sentences = [{moored, <<"alongside at macao">>},
                 {consigned, <<"consigned at macao">>},
                 {in_passage, <<"at sea, bound for lisbon">>},
                 {made_landfall, <<"still knocking">>},
                 {was_lost, <<"lost to pirates">>},
                 {never_sailed, <<"never sailed">>},
                 {unknown, <<"nobody asked yet">>}],
    _ = [?assert(contains(flat(show_house_page:board(standing_view(Standing))), Says))
         || {Standing, Says} <- Sentences],
    ok.

%% A ship at sea shows when she is due and how long is left, and NEVER how long
%% a crossing takes. That number is the ocean's constant and recovering it here
%% by subtracting two of the ocean's own timestamps is exactly the leak that
%% putting an instant on the wire exists to prevent.
a_ship_at_sea_shows_a_countdown_test() ->
    Board = flat(show_house_page:board(standing_view(in_passage))),
    ?assert(contains(Board, <<"due ">>)),
    ?assert(contains(Board, <<"class=\"countdown\"">>)),
    ?assert(contains(Board, <<"to go">>)).

%% NOTHING OFF THE MESH REACHES THE PAGE UNESCAPED. A harbour is another
%% player's process on another player's laptop.
markup_from_the_mesh_cannot_reach_the_page_test() ->
    Nasty = <<"<script>alert('purse')</script>">>,
    View = (moored_view())#{news => [#{fact    => ship_moored,
                                       at      => 1786528800000,
                                       payload => #{<<"harbour">> => Nasty}}]},
    Board = flat(show_house_page:board(View)),
    ?assertNot(contains(Board, <<"<script>alert">>)),
    ?assert(contains(Board, <<"&lt;script&gt;">>)).

a_port_that_will_not_answer_is_said_out_loud_test() ->
    View = (moored_view())#{trouble => #{read_quotes => #{reason => {?LISBON, timeout},
                                                          at => 1786528800000}}},
    Board = flat(show_house_page:board(View)),
    ?assert(contains(Board, <<"Not everything answered">>)),
    ?assert(contains(Board, <<"read_quotes">>)).

%% An empty house is a page, not a crash. This is what a player sees in the
%% first two seconds, before anybody has answered anything.
an_empty_house_still_renders_test() ->
    View = #{names => names(), purse => 1000.0, hull => undefined, cargo => #{},
             hold => 0.0, free_hold => 0.0,
             sight => tom_house:sight(tom_house:empty()),
             orders => [], quotes => #{}, news => [], trouble => #{},
             at => 1786528800000},
    Page = flat(show_house_page:page(View)),
    ?assert(contains(Page, <<"nobody asked yet">>)),
    ?assert(contains(Page, <<"Empty.">>)).

%%% Numbers a person reads

money_is_always_two_places_test() ->
    ?assertEqual(<<"418.58">>, flat(show_house_page:money(418.58))),
    ?assertEqual(<<"1000.00">>, flat(show_house_page:money(1000.0))).

%% Two decimals would round away the difference a small trade makes, which is
%% the difference a trader is looking at.
a_price_keeps_four_places_test() ->
    ?assertEqual(<<"12.9155">>, flat(show_house_page:price(12.915496650148841))).

tons_lose_their_trailing_zeroes_test() ->
    ?assertEqual(<<"40">>, flat(show_house_page:quantity(40.0))),
    ?assertEqual(<<"12.5">>, flat(show_house_page:quantity(12.5))),
    ?assertEqual(<<"43.918">>, flat(show_house_page:quantity(43.918))).

nothing_known_is_a_dash_not_a_zero_test() ->
    ?assertEqual(<<"&mdash;">>, flat(show_house_page:money(undefined))),
    ?assertEqual(<<"&mdash;">>, flat(show_house_page:price(undefined))),
    ?assertEqual(<<"&mdash;">>, flat(show_house_page:quantity(undefined))),
    ?assertEqual(<<"&mdash;">>, flat(show_house_page:clock(undefined))).

%%% What a player is told when something goes wrong

a_refusal_is_said_in_english_test() ->
    ?assert(contains(show_house_page:say({ship_is_not_alongside, in_passage}),
                     <<"not lying at a port">>)),
    ?assert(contains(show_house_page:say({not_enough_coin, 581.42}),
                     <<"581.42">>)),
    ?assert(contains(show_house_page:say({already_there, ?MACAO}), <<"macao">>)),
    ?assert(contains(show_house_page:say(no_mesh), <<"mesh">>)),
    ?assert(contains(show_house_page:say(timeout), <<"in time">>)).

%% THE ENUMERATED REASONS REACH THE PLAYER IN ENGLISH. They arrive whole because
%% a port answers a refusal with a reply carrying the reason, rather than with
%% `{error, Reason}', whose reason macula renders into a frame's `detail' and
%% the SDK's caller path then drops.
each_reason_a_port_gives_is_said_in_english_test() ->
    [?assert(contains(show_house_page:say(Reason), Word))
     || {Reason, Word} <- [{<<"hold_full">>, <<"room">>},
                           {<<"not_in_hold">>, <<"aboard">>},
                           {<<"quay_empty">>, <<"quay">>},
                           {<<"not_here">>, <<"holding her">>},
                           {<<"not_yours">>, <<"not this house">>},
                           {<<"ship_consigned">>, <<"frozen">>},
                           {<<"unknown_good">>, <<"does not trade">>}]].

%% A reason nobody has written a sentence for is still shown rather than
%% swallowed: the producer owns the content of what it sends, and a port is free
%% to refuse for a reason this house has never heard of.
a_reason_with_no_sentence_is_still_shown_test() ->
    ?assert(contains(show_house_page:say(<<"quarantine">>), <<"quarantine">>)).

%% The hole this used to describe is closed: since macula 8.0.0 a refusal
%% carries its reason. A bare error code now means the far port is on an older
%% mesh, and the page says which of the two is behind rather than blaming the
%% mesh for a limit it no longer has.
a_refusal_with_no_reason_on_it_names_the_older_side_test() ->
    Said = show_house_page:say({call_error, 16#0F, unknown_error}),
    ?assert(contains(Said, <<"said no">>)),
    ?assert(contains(Said, <<"older mesh">>)).

anything_unexpected_is_still_shown_test() ->
    ?assert(contains(show_house_page:say({something, new, 42}), <<"something">>)).

%%% The same thing as JSON

the_json_view_encodes_test() ->
    Json = show_house_json:snapshot(moored_view()),
    Encoded = iolist_to_binary(json:encode(Json)),
    ?assert(contains(Encoded, <<"\"purse\":418.58">>)),
    ?assert(contains(Encoded, <<"\"standing\":\"moored\"">>)),
    ?assert(contains(Encoded, <<"\"where\":\"macao\"">>)).

%% Nothing this house does not know is invented; it is null.
the_json_view_says_null_for_what_it_does_not_know_test() ->
    Json = show_house_json:snapshot(moored_view()),
    ?assertEqual(null, maps:get(<<"bound_for">>, maps:get(<<"ship_is">>, Json))),
    ?assertEqual(null, maps:get(<<"due_in_ms">>, maps:get(<<"ship_is">>, Json))).

%% Time left is computed against the snapshot's own instant, so a consumer never
%% has to reconcile its clock with the ocean's.
the_json_view_counts_down_against_its_own_instant_test() ->
    Json = show_house_json:snapshot(standing_view(in_passage)),
    ?assertEqual(90000, maps:get(<<"due_in_ms">>, maps:get(<<"ship_is">>, Json))).

%% An error reason is an Erlang term. Rendering it faithfully beats dropping it.
the_json_view_spells_out_a_refusal_test() ->
    View = (moored_view())#{orders => [#{order => <<"a">>, kind => purchase,
                                         harbour => ?MACAO, good => ?PEPPER,
                                         quantity => 40.0, at => 1786528800000,
                                         state => refused,
                                         reason => {call_error, 15, unknown_error}}]},
    [Order] = maps:get(<<"orders">>, show_house_json:snapshot(View)),
    ?assert(contains(maps:get(<<"reason">>, Order), <<"call_error">>)),
    ?assertEqual(<<"refused">>, maps:get(<<"state">>, Order)).

%%% Only this house's own ship is this house's business

only_our_own_ship_is_watched_test() ->
    ?assert(watch_ports:ours(#{<<"ship">> => ?SHIP}, ?SHIP)),
    ?assertNot(watch_ports:ours(#{<<"ship">> => <<"mri:instance:io.macula/tom/ship/x">>},
                                ?SHIP)),
    ?assertNot(watch_ports:ours(#{}, ?SHIP)).

%% ship_moored_v1 carries the whole ship map where the others carry the
%% identifier, because the port that just took custody has the map.
a_moored_fact_carries_the_ship_map_test() ->
    ?assert(watch_ports:ours(#{<<"ship">> => #{<<"ship">> => ?SHIP}}, ?SHIP)),
    ?assertNot(watch_ports:ours(#{<<"ship">> => #{<<"hop">> => 3}}, ?SHIP)).

%%% Fixtures

moored_view() ->
    #{names     => names(),
      purse     => 418.58,
      hull      => hull(),
      cargo     => #{?PEPPER => 40.0},
      hold      => 200.0,
      free_hold => 160.0,
      sight     => #{standing => moored, where => ?MACAO, bound_for => undefined,
                     sailed_at => undefined, due_at => undefined, cause => undefined,
                     sighted_at => 1786528800000, ship => ?SHIP},
      orders    => [#{order => <<"5f2c1a">>, kind => purchase, harbour => ?MACAO,
                      good => ?PEPPER, quantity => 40.0, at => 1786528800000,
                      state => settled, coin => 581.42, moved => 40.0}],
      quotes    => #{?MACAO => #{quotes => [#{<<"good">> => ?PEPPER,
                                              <<"price">> => 12.915496650148841,
                                              <<"stock">> => 43.918}],
                                 told_at => 1786528800000,
                                 seen_at => 1786528797000},
                     ?LISBON => #{quotes => [], told_at => undefined,
                                  seen_at => 1786528797000}},
      news      => [#{fact => you_bought, at => 1786528800000,
                      payload => #{good => ?PEPPER, harbour => ?MACAO,
                                   quantity => 40.0, coin => 581.42}}],
      trouble   => #{},
      at        => 1786528800000}.

standing_view(Standing) ->
    View = moored_view(),
    View#{sight => (maps:get(sight, View))#{standing  => Standing,
                                            where     => where(Standing),
                                            bound_for => bound(Standing),
                                            sailed_at => 1786528800000,
                                            due_at    => due(Standing),
                                            cause     => cause(Standing)}}.

where(moored)     -> ?MACAO;
where(consigned)  -> ?MACAO;
where(in_passage) -> ?OCEAN;
where(_Other)     -> ?OCEAN.

bound(moored)       -> undefined;
bound(never_sailed) -> undefined;
bound(unknown)      -> undefined;
bound(_Other)       -> ?LISBON.

due(in_passage) -> 1786528890000;
due(_Other)     -> undefined.

cause(was_lost) -> <<"pirates">>;
cause(_Other)   -> undefined.

hull() ->
    #{<<"ship">> => ?SHIP, <<"owner">> => ?HOUSE, <<"hold">> => 200.0,
      <<"cargo">> => #{?PEPPER => 40.0}, <<"hop">> => 6,
      <<"custodian">> => ?MACAO}.

names() ->
    {ok, Names} = tom_names:read(#{realm_name => <<"io.macula">>,
                                   player     => <<"raf">>,
                                   ship       => <<"santa_clara">>,
                                   harbours   => [<<"macao">>, <<"lisbon">>],
                                   goods      => [<<"pepper">>, <<"nutmeg">>]}),
    Names.

flat(IoData) -> iolist_to_binary(IoData).

contains(Haystack, Needle) -> binary:match(Haystack, Needle) =/= nomatch.
