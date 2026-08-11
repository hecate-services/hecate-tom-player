%% @doc Sell a good out of the ship's hold, onto the quay of the port it is
%% lying in, and watch the purse rise.
%%
%% The mirror of buying, and deliberately its own slice rather than a direction
%% flag on one. The two differ in what can go wrong: a purchase can be refused
%% for want of money and has to be priced before it is placed, while a sale can
%% only ever increase the purse. That is why there is no `quote_sale' in the
%% contract and no price check here: there is nothing to protect the player
%% against.
%%
%% Same reliability pattern, same key, same replay. An order left in flight by a
%% crash is re-called with its original key at boot, and the harbour replays the
%% receipt it already stored.
%% @end
-module(sell_cargo).

-export([order/2, settle/1]).

%% @doc Order a quantity of one good out of the hold, here, now.
-spec order(binary(), number()) -> {ok, map()} | {refused, term()} | {pending, term()}.
order(GoodMRI, Quantity) ->
    alongside(tom_house:sight(keep_house:house()), GoodMRI, Quantity).

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
    concluded(tom_wire:call(tom_names:procedure(Harbour, <<"sell_cargo">>), Payload, act),
              Order).

%%% Internal

%% What is in the hold is the harbour's fact, not this house's, so `not_in_hold'
%% is the harbour's answer to give. This clause only catches the case the house
%% genuinely knows about: a ship that is not lying at a port at all.
alongside(#{standing := moored, where := Harbour}, Good, Quantity)
  when is_binary(Harbour) ->
    At  = erlang:system_time(millisecond),
    Key = keep_house:mint_order(),
    ok  = keep_house:record({sale_ordered_v1,
                             #{order    => Key,
                               harbour  => Harbour,
                               good     => Good,
                               quantity => float(Quantity),
                               at       => At}}),
    settle(#{order => Key, kind => sale, harbour => Harbour, good => Good,
             quantity => float(Quantity), at => At, state => ordered});
alongside(#{standing := Standing}, _Good, _Quantity) ->
    {refused, {ship_is_not_alongside, Standing}}.

concluded({ok, Receipt}, Order) ->
    ok = keep_house:note_all_well(sell_cargo),
    banked(number_at(<<"coin">>, Receipt), Receipt, Order);
concluded({refused, Why}, #{order := Key}) ->
    ok = keep_house:record({sale_refused_v1,
                            #{order  => Key,
                              reason => Why,
                              at     => erlang:system_time(millisecond)}}),
    {refused, Why};
concluded({unreachable, Why}, _Order) ->
    ok = keep_house:note_trouble(sell_cargo, Why),
    {pending, Why}.

banked({ok, Coin}, Receipt, #{order := Key, harbour := Harbour, good := Good}) ->
    Discharged = discharged(Receipt),
    ok = keep_house:record({sale_settled_v1,
                            #{order      => Key,
                              coin       => Coin,
                              discharged => Discharged,
                              at         => erlang:system_time(millisecond)}}),
    ok = alongside_now(maps:get(<<"ship">>, Receipt, undefined), Harbour),
    ok = keep_house:note_news(you_sold, #{good     => Good,
                                          harbour  => Harbour,
                                          quantity => Discharged,
                                          coin     => Coin}),
    {ok, Receipt};
banked(error, Receipt, _Order) ->
    ok = keep_house:note_trouble(sell_cargo, {receipt_without_a_price, Receipt}),
    {pending, receipt_without_a_price}.

alongside_now(Hull, Harbour) when is_map(Hull) ->
    keep_house:sight(#{standing => moored,
                       where    => Harbour,
                       hull     => Hull,
                       at       => erlang:system_time(millisecond)});
alongside_now(_NotAShip, _Harbour) ->
    ok.

discharged(Receipt) -> maps:get(<<"discharged">>, Receipt, 0.0).

number_at(Key, Map) -> a_number(maps:get(Key, Map, undefined)).

a_number(N) when is_number(N) -> {ok, float(N)};
a_number(_Other)              -> error.
