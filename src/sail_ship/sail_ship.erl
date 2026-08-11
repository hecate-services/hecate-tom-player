%% @doc Send the ship from the port it is lying in to another one.
%%
%% NO IDEMPOTENCY KEY, and that is not an oversight. The ship's own state is the
%% key. Called again with the same destination while the ship is already
%% consigned, the harbour returns the same answer; called after the ship has
%% gone, it returns `not_here' and the house asks the ocean instead. There is
%% nothing for this house to mint and nothing for it to remember, which is why
%% sailing has no ordered/settled pair the way a trade does.
%%
%% A "no answer" here is not a failure to sail. The harbour may well have
%% consigned the ship and lost the reply on the way back. So an unreachable
%% answer does NOT get retried blindly: it hands the question to `find_ship',
%% which asks the ocean and the ports where the hull actually is. Asking is
%% cheaper and truer than assuming.
%% @end
-module(sail_ship).

-export([to/1]).

%% @doc Consign the ship toward a harbour.
-spec to(binary()) -> {ok, map()} | {refused, term()} | {pending, term()}.
to(BoundFor) ->
    shaped(tom_names:is_harbour(BoundFor), BoundFor).

%%% Internal

%% A parse, not a lookup. This house has no directory and cannot know whether
%% Lisbon exists, only whether the name is the shape a harbour's name has. The
%% harbour applies the same rule at its end and for the same reason.
shaped(false, BoundFor) ->
    {refused, {not_a_harbour, BoundFor}};
shaped(true, BoundFor) ->
    alongside(tom_house:sight(keep_house:house()), BoundFor).

alongside(#{standing := moored, where := Harbour}, BoundFor)
  when is_binary(Harbour), Harbour =/= BoundFor ->
    Names = keep_house:names(),
    Payload = #{<<"by">>        => maps:get(house, Names),
                <<"ship">>      => maps:get(ship, Names),
                <<"bound_for">> => BoundFor},
    consigned(tom_wire:call(tom_names:procedure(Harbour, <<"sail_ship">>), Payload, act),
              Harbour, BoundFor);
alongside(#{standing := moored, where := Harbour}, BoundFor)
  when Harbour =:= BoundFor ->
    {refused, {already_there, BoundFor}};
alongside(#{standing := Standing}, _BoundFor) ->
    {refused, {ship_is_not_alongside, Standing}}.

%% The harbour is still the custodian at this point and stays one until the
%% ocean's durable acceptance. The ship is frozen: nothing can be bought into it,
%% sold out of it, or consigned a second time. If the ocean is down that state
%% persists visibly, and the page showing "consigned at Macao" for an hour is the
%% correct report of the world.
consigned({ok, Reply}, Harbour, BoundFor) ->
    ok = keep_house:sight(#{standing  => consigned,
                            where     => Harbour,
                            bound_for => BoundFor,
                            at        => erlang:system_time(millisecond)}),
    ok = keep_house:note_news(you_sailed, #{from      => Harbour,
                                            bound_for => BoundFor}),
    ok = find_ship:look(),
    {ok, Reply};
consigned({refused, Why}, _Harbour, _BoundFor) ->
    {refused, Why};
consigned({unreachable, Why}, _Harbour, _BoundFor) ->
    ok = keep_house:note_trouble(sail_ship, Why),
    ok = find_ship:look(),
    {pending, Why}.
