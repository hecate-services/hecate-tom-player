%% @doc The five things a player can do, and saying plainly how each went.
%%
%%   quote  what would this cost, before any money moves
%%   buy    into the hold, at the port she is lying in
%%   sell   out of the hold, at the port she is lying in
%%   sail   send her to sea, bound for another port
%%   ask    go and ask everybody where she is and what things cost
%%
%% THE FORMS WORK WITHOUT JAVASCRIPT. A plain browser posts and is sent back to
%% the page; a browser with the script posts the same body, asks for JSON and
%% writes the answer in place. One handler, one code path, and the fallback is
%% not a second implementation.
%%
%% Reasons are turned into English by `show_house_page:say/1', which is the one
%% place in the house where an Erlang term becomes something a person reads.
%% @end
-module(show_house_act).

-export([init/2]).

init(Req0, State) ->
    {ok, Fields, Req} = cowboy_req:read_urlencoded_body(Req0),
    Outcome = did(field(<<"do">>, Fields), Fields),
    {ok, answered(json_wanted(Req), Outcome, Req), State}.

%%% Internal

did(<<"quote">>, Fields) ->
    quoted(with_good(Fields, fun buy_cargo:what_would_it_cost/2));
did(<<"buy">>, Fields) ->
    traded(<<"Bought">>, with_good(Fields, fun buy_cargo:order/2));
did(<<"sell">>, Fields) ->
    traded(<<"Sold">>, with_good(Fields, fun sell_cargo:order/2));
did(<<"sail">>, Fields) ->
    sailed(with_harbour(Fields));
did(<<"ask">>, _Fields) ->
    ok = find_ship:look(),
    ok = read_quotes:ask_now(),
    {true, <<"Asked every port.">>};
did(_Anything_else, _Fields) ->
    {false, <<"That is not something this house does.">>}.

%% Resolve the good and the quantity once, here, so the three trading verbs
%% below all fail the same way on the same bad input.
with_good(Fields, Act) ->
    Names = keep_house:names(),
    good_and_tons(lists:keyfind(field(<<"good">>, Fields), 1, maps:get(goods, Names)),
                  tons(field(<<"quantity">>, Fields)),
                  Act).

good_and_tons(false, _Tons, _Act) ->
    {refused, {unknown_good, unnamed}};
good_and_tons(_Good, error, _Act) ->
    {refused, {bad_quantity, unnamed}};
good_and_tons({_Local, MRI}, {ok, Tons}, Act) ->
    Act(MRI, Tons).

with_harbour(Fields) ->
    Names = keep_house:names(),
    bound(lists:keyfind(field(<<"bound_for">>, Fields), 1, maps:get(harbours, Names))).

bound(false)          -> {refused, {not_a_harbour, unnamed}};
bound({_Local, MRI})  -> sail_ship:to(MRI).

quoted({ok, Quote}) ->
    Coin = maps:get(<<"coin">>, Quote, undefined),
    After = maps:get(<<"price_after">>, Quote, undefined),
    {true, iolist_to_binary([<<"That would cost ">>, show_house_page:money(Coin),
                             <<", and would leave the price at ">>,
                             show_house_page:price(After), <<".">>])};
quoted(Answer) ->
    stumbled(Answer).

%% WHAT WAS ASKED FOR IS NOT WHAT MOVED, and a quay holds what it holds, so an
%% order for five tons at a shallow port fills two and a half. The confirmation
%% used to say "Sold it, for 209.38" and leave the player to notice from the
%% orders table that only 2.545 tons had left the hold. The number a player reads
%% first must be the true one.
traded(Verb, {ok, Receipt}) ->
    {true, iolist_to_binary([Verb, <<" ">>, show_house_page:quantity(moved(Receipt)),
                             <<" for ">>,
                             show_house_page:money(maps:get(<<"coin">>, Receipt,
                                                            undefined)),
                             <<".">>])};
traded(_Verb, Answer) ->
    stumbled(Answer).

sailed({ok, _Reply}) ->
    {true, <<"She has sailed.">>};
sailed(Answer) ->
    stumbled(Answer).

stumbled({refused, Why}) ->
    {false, show_house_page:say(Why)};
stumbled({pending, Why}) ->
    {false, <<"No answer yet, so the house will keep asking. (",
              (show_house_page:say(Why))/binary, ")">>}.

%% A buy says how much it filled and a sell how much it discharged. Whichever
%% word the far port used, it is the number of tons that actually left or entered
%% the hold, and it is the one a player must be shown first.
moved(#{<<"filled">> := Tons})     -> Tons;
moved(#{<<"discharged">> := Tons}) -> Tons;
moved(_Receipt_without_one)        -> undefined.

field(Name, Fields) -> proplists:get_value(Name, Fields, <<>>).

%% Accepts "10" and "10.5" alike, and refuses everything else including nothing
%% at all and a negative number of tons.
tons(Bin) -> weighed(string:to_float(binary_to_list(Bin)), Bin).

weighed({Float, _Rest}, _Bin) when is_float(Float) -> positive(Float);
weighed({error, _Why}, Bin)                        -> whole(string:to_integer(
                                                              binary_to_list(Bin))).

whole({Int, _Rest}) when is_integer(Int) -> positive(float(Int));
whole(_Anything_else)                    -> error.

positive(Tons) when Tons > 0.0 -> {ok, Tons};
positive(_Tons)                -> error.

json_wanted(Req) ->
    Accept = cowboy_req:header(<<"accept">>, Req, <<>>),
    binary:match(Accept, <<"application/json">>) =/= nomatch.

%% Without the script, the browser is sent back to the page it came from and
%% reads the outcome in the ticker. With it, the answer arrives in place.
answered(true, {Ok, Message}, Req) ->
    cowboy_req:reply(200,
                     #{<<"content-type">> => <<"application/json">>},
                     json:encode(#{<<"ok">> => Ok, <<"message">> => Message}),
                     Req);
answered(false, {_Ok, _Message}, Req) ->
    cowboy_req:reply(303, #{<<"location">> => <<"/">>}, <<>>, Req).

