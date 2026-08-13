%% @doc Send the ship from the port it is lying in to another one.
%%
%% NO IDEMPOTENCY KEY, and that is not an oversight. The ship's own state is the
%% key. Called again with the same destination while the ship is already
%% consigned, the harbour returns the same answer; called after the ship has
%% gone, it returns `not_here' and the house asks the other ports. There is
%% nothing for this house to mint and nothing for it to remember, which is why
%% sailing has no ordered/settled pair the way a trade does.
%%
%% A "no answer" here is not a failure to sail. The harbour may well have
%% consigned the ship and lost the reply on the way back. So an unreachable
%% answer does NOT get retried blindly: it hands the question to `find_ship',
%% which asks the ports where the hull actually is. Asking is
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
    sailed(tom_wire:call(tom_names:procedure(Harbour, <<"sail_ship">>), Payload, act),
              Harbour, BoundFor);
alongside(#{standing := moored, where := Harbour}, BoundFor)
  when Harbour =:= BoundFor ->
    {refused, {already_there, BoundFor}};
alongside(#{standing := Standing}, _BoundFor) ->
    {refused, {ship_is_not_alongside, Standing}}.

%% SHE IS AT SEA THE INSTANT THE PORT SAYS SO, and the port's reply carries the
%% hour she is due, so the page can count down without this house ever knowing
%% how long a crossing takes.
%%
%% The port she left is still her custodian and stays one until the far port's
%% durable acceptance. She is frozen: nothing can be bought into her, sold out of
%% her, or promised anywhere else. If the far port is dark she stays at sea and
%% overdue, visibly, which is the correct report of the world.
sailed({ok, Reply}, Harbour, BoundFor) ->
    ok = keep_house:sight(#{standing  => in_passage,
                            where     => Harbour,
                            bound_for => BoundFor,
                            sailed_at => maps:get(<<"at">>, Reply, undefined),
                            due_at    => maps:get(<<"due_at">>, Reply, undefined),
                            path      => maps:get(<<"path">>, Reply, []),
                            at        => erlang:system_time(millisecond)}),
    ok = keep_house:note_news(you_sailed, #{from      => Harbour,
                                            bound_for => BoundFor}),
    ok = find_ship:look(),
    ok = keep_house:note_all_well(sail_ship),
    {ok, Reply};
sailed({refused, Why}, _Harbour, _BoundFor) ->
    {refused, Why};
sailed({unreachable, Why}, _Harbour, _BoundFor) ->
    ok = keep_house:note_trouble(sail_ship, Why),
    ok = find_ship:look(),
    {pending, Why}.
