%% @doc Buy a good at the port the ship is lying in, straight into its hold.
%%
%% THERE IS NO WAREHOUSE. You do not buy goods and then load them; buying IS
%% loading. The quay hands the cargo to the hull in one local act inside the
%% harbour's own process, so the only thing that crosses the wire is a receipt
%% and the only thing this house does with it is move its own number. That is
%% what makes a purchase a single transaction with no shared library and no
%% two-phase commit between two machines.
%%
%% == The pattern, and why it is safe ==
%%
%%   1. mint a key and write the intent to disk
%%   2. call, with that key
%%   3. on a definite answer, write the conclusion and move the purse
%%
%% A house that dies anywhere in there comes back, finds an order with no
%% conclusion, and calls again with the SAME key. The harbour stored its receipt
%% under that key and replays it, so the second call moves no goods and the purse
%% moves exactly once.
%%
%% NAME THE CONSEQUENCE RATHER THAN HIDE IT: an order that was in flight when the
%% house died will EXECUTE when the house comes back, at whatever the price is
%% then. The house cannot instead ask "did you do this?" and drop it on a no,
%% because that races a call the harbour is still processing and would put cargo
%% in the hold that nobody ever paid for.
%%
%% == What is checked here and what is not ==
%%
%% The purse is checked here, because this house owns the purse. The hold is NOT
%% checked here, even though this house has a picture of it, because the harbour
%% owns the ship while it is moored and its picture is the true one. Refusing a
%% legal purchase against a stale local copy of somebody else's fact is worse
%% than a round trip.
%% @end
-module(buy_cargo).

-export([order/2, settle/1, what_would_it_cost/2]).

%% @doc What a quantity of one good would cost at the port she is lying in.
%%
%% Moves nothing. This is the only way a player can know the price of an order
%% before placing it, because a trade pays the prices it walks through and the
%% posted price times the quantity is not the answer.
-spec what_would_it_cost(binary(), number()) -> tom_wire:answer().
what_would_it_cost(GoodMRI, Quantity) ->
    where_moored(tom_house:sight(keep_house:house()), GoodMRI, Quantity).

%% @doc Order a quantity of one good into the hold, here, now.
-spec order(binary(), number()) -> {ok, map()} | {refused, term()} | {pending, term()}.
order(GoodMRI, Quantity) ->
    House = keep_house:house(),
    alongside(tom_house:sight(House), tom_house:purse(House), GoodMRI, Quantity).

%% @doc Drive one order to a conclusion. Called when it is placed, and called
%% again at boot for every order that never reached one.
-spec settle(tom_house:order()) -> {ok, map()} | {refused, term()} | {pending, term()}.
settle(#{order := Key, harbour := Harbour, good := Good, quantity := Quantity} = Order) ->
    Names = keep_house:names(),
    Payload = #{<<"order">>    => Key,
                <<"by">>       => maps:get(house, Names),
                <<"ship">>     => maps:get(ship, Names),
                <<"good">>     => Good,
                <<"quantity">> => float(Quantity)},
    concluded(tom_wire:call(tom_names:procedure(Harbour, <<"buy_cargo">>), Payload, act),
              Order).

%%% Internal

where_moored(#{standing := moored, where := Harbour}, Good, Quantity)
  when is_binary(Harbour) ->
    ask_price(Harbour, Good, Quantity);
where_moored(#{standing := Standing}, _Good, _Quantity) ->
    {refused, {ship_is_not_alongside, Standing}}.

%% Buying happens at the port that is holding the ship. Any other standing is a
%% mistake the player can see and correct, so it is answered here rather than
%% sent to a harbour that would answer `not_here'.
alongside(#{standing := moored, where := Harbour}, Purse, Good, Quantity)
  when is_binary(Harbour) ->
    priced(ask_price(Harbour, Good, Quantity), Purse, Harbour, Good, Quantity);
alongside(#{standing := Standing}, _Purse, _Good, _Quantity) ->
    {refused, {ship_is_not_alongside, Standing}}.

%% A trade pays the prices it walks through, not the posted price times the
%% quantity, so a house CANNOT compute what an order will cost. That is the whole
%% reason quote_purchase exists, and the reason this is a call and not a
%% multiplication.
ask_price(Harbour, Good, Quantity) ->
    tom_wire:call(tom_names:procedure(Harbour, <<"quote_purchase">>),
                  #{<<"good">> => Good, <<"quantity">> => float(Quantity)},
                  read).

priced({ok, Quote}, Purse, Harbour, Good, Quantity) ->
    weighed(number_at(<<"coin">>, Quote), Quote, Purse, Harbour, Good, Quantity);
priced({refused, Why}, _Purse, _Harbour, _Good, _Quantity) ->
    {refused, Why};
priced({unreachable, Why}, _Purse, _Harbour, _Good, _Quantity) ->
    {pending, Why}.

weighed({ok, Coin}, _Quote, Purse, Harbour, Good, Quantity) ->
    solvent(Coin =< Purse, Coin, Harbour, Good, Quantity);
weighed(error, Quote, _Purse, _Harbour, _Good, _Quantity) ->
    {refused, {quote_without_a_price, Quote}}.

solvent(false, Coin, _Harbour, _Good, _Quantity) ->
    {refused, {not_enough_coin, Coin}};
solvent(true, _Coin, Harbour, Good, Quantity) ->
    At  = erlang:system_time(millisecond),
    Key = keep_house:mint_order(),
    ok  = keep_house:record({purchase_ordered_v1,
                             #{order    => Key,
                               harbour  => Harbour,
                               good     => Good,
                               quantity => float(Quantity),
                               at       => At}}),
    settle(#{order => Key, kind => purchase, harbour => Harbour, good => Good,
             quantity => float(Quantity), at => At, state => ordered}).

concluded({ok, Receipt}, Order) ->
    banked(number_at(<<"coin">>, Receipt), Receipt, Order);
concluded({refused, Why}, #{order := Key}) ->
    ok = keep_house:record({purchase_refused_v1,
                            #{order  => Key,
                              reason => Why,
                              at     => erlang:system_time(millisecond)}}),
    {refused, Why};
concluded({unreachable, Why}, _Order) ->
    ok = keep_house:note_trouble(buy_cargo, Why),
    {pending, Why}.

%% A receipt with no price in it is not a receipt. The order stays OPEN and gets
%% retried, because closing it would either lose money that was spent or invent a
%% refusal the harbour never made. The player sees a stuck order and the reason,
%% which is the truth.
banked({ok, Coin}, Receipt, #{order := Key, harbour := Harbour, good := Good}) ->
    Filled = filled(Receipt),
    ok = keep_house:record({purchase_settled_v1,
                            #{order  => Key,
                              coin   => Coin,
                              filled => Filled,
                              at     => erlang:system_time(millisecond)}}),
    ok = alongside_now(maps:get(<<"ship">>, Receipt, undefined), Harbour),
    ok = keep_house:note_news(you_bought, #{good     => Good,
                                            harbour  => Harbour,
                                            quantity => Filled,
                                            coin     => Coin}),
    {ok, Receipt};
banked(error, Receipt, _Order) ->
    ok = keep_house:note_trouble(buy_cargo, {receipt_without_a_price, Receipt}),
    {pending, receipt_without_a_price}.

%% The receipt carries the ship as it now is, from the service that has custody
%% of it. That is a better picture than anything this house could assemble, so it
%% goes straight in.
alongside_now(Hull, Harbour) when is_map(Hull) ->
    keep_house:sight(#{standing => moored,
                       where    => Harbour,
                       hull     => Hull,
                       at       => erlang:system_time(millisecond)});
alongside_now(_NotAShip, _Harbour) ->
    ok.

filled(Receipt) -> maps:get(<<"filled">>, Receipt, 0.0).

number_at(Key, Map) -> a_number(maps:get(Key, Map, undefined)).

a_number(N) when is_number(N) -> {ok, float(N)};
a_number(_Other)              -> error.
