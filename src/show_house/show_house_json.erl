%% @doc The same snapshot the page shows, as JSON, for a shell.
%%
%% This exists so a human can `curl localhost:8461/view' and see what the house
%% believes without reading HTML or attaching to a node. That makes the service
%% inspectable from a terminal, which is where anybody debugging it already is.
%%
%% An EXPLICIT projection, deliberately, rather than a generic term-to-JSON
%% converter. A generic one would either crash on the first tuple in an error
%% reason or quietly stringify things nobody meant to publish; naming every field
%% means the endpoint's shape is a decision somebody made and a test can hold.
%%
%% MRIs are shortened to their last segment here. The full identifier is the
%% mesh's business and the short name is what a person reads.
%% @end
-module(show_house_json).

-export([snapshot/1]).

-spec snapshot(map()) -> map().
snapshot(View) ->
    Names = maps:get(names, View),
    #{<<"player">>  => tom_names:local(maps:get(house, Names)),
      <<"ship">>    => tom_names:local(maps:get(ship, Names)),
      <<"purse">>   => maps:get(purse, View),
      <<"ship_is">> => whereabouts(maps:get(sight, View), maps:get(at, View)),
      <<"hold">>    => hold(View),
      <<"market">>  => market(View),
      <<"orders">>  => [order(O) || O <- maps:get(orders, View)],
      <<"trouble">> => trouble(maps:get(trouble, View, #{})),
      <<"at">>      => maps:get(at, View)}.

%%% Internal

%% `due_in_ms' is computed here, against the snapshot's own instant, so a
%% consumer never has to reconcile its clock with the ocean's. The length of a
%% crossing is NOT here and must not be: it is the ocean's constant and it stays
%% there.
whereabouts(Sight, Now) ->
    #{<<"standing">>   => atom_to_binary(maps:get(standing, Sight), utf8),
      <<"where">>      => shortened(maps:get(where, Sight)),
      <<"bound_for">>  => shortened(maps:get(bound_for, Sight)),
      <<"sailed_at">>  => nullable(maps:get(sailed_at, Sight)),
      <<"due_at">>     => nullable(maps:get(due_at, Sight)),
      <<"due_in_ms">>  => left(maps:get(due_at, Sight), Now),
      <<"cause">>      => nullable(maps:get(cause, Sight)),
      <<"sighted_at">> => nullable(maps:get(sighted_at, Sight))}.

hold(View) ->
    #{<<"capacity">> => maps:get(hold, View, 0.0),
      <<"free">>     => maps:get(free_hold, View, 0.0),
      <<"cargo">>    => maps:from_list(
                          [{tom_names:local(Good), Tons}
                           || {Good, Tons} <- maps:to_list(maps:get(cargo, View, #{}))])}.

market(View) ->
    Names  = maps:get(names, View),
    Quotes = maps:get(quotes, View, #{}),
    maps:from_list([{Local, posted(maps:get(MRI, Quotes, #{}))}
                    || {Local, MRI} <- maps:get(harbours, Names)]).

posted(Posted) ->
    #{<<"seen_at">> => nullable(maps:get(seen_at, Posted, undefined)),
      <<"told_at">> => nullable(maps:get(told_at, Posted, undefined)),
      <<"goods">>   => maps:from_list([{tom_names:local(maps:get(<<"good">>, Q, <<>>)),
                                        #{<<"price">> => maps:get(<<"price">>, Q, null),
                                          <<"stock">> => maps:get(<<"stock">>, Q, null)}}
                                       || Q <- maps:get(quotes, Posted, [])])}.

order(Order) ->
    #{<<"order">>    => maps:get(order, Order),
      <<"kind">>     => atom_to_binary(maps:get(kind, Order), utf8),
      <<"harbour">>  => tom_names:local(maps:get(harbour, Order)),
      <<"good">>     => tom_names:local(maps:get(good, Order)),
      <<"quantity">> => tom_house:moved(Order),
      <<"state">>    => atom_to_binary(maps:get(state, Order), utf8),
      <<"at">>       => maps:get(at, Order),
      <<"coin">>     => maps:get(coin, Order, null),
      <<"reason">>   => spelled(maps:get(reason, Order, undefined))}.

trouble(Trouble) ->
    maps:from_list([{atom_to_binary(Where, utf8),
                     #{<<"reason">> => spelled(maps:get(reason, What)),
                       <<"at">>     => maps:get(at, What)}}
                    || {Where, What} <- maps:to_list(Trouble)]).

shortened(undefined) -> null;
shortened(MRI)       -> tom_names:local(MRI).

nullable(undefined) -> null;
nullable(Value)     -> Value.

left(undefined, _Now) -> null;
left(Due, Now)        -> Due - Now.

spelled(undefined)               -> null;
spelled(Reason) when is_binary(Reason) -> Reason;
spelled(Reason)                  -> iolist_to_binary(io_lib:format("~0p", [Reason])).
