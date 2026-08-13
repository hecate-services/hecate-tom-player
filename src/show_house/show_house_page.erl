%% @doc The page, rendered. Pure: a view in, iodata out.
%%
%% This exists so the thing a human actually looks at can be tested without a
%% browser, a station or a port. Every function here is a function of one term.
%%
%% THE PAGE IS RENDERED ON THE SERVER AND SWAPPED WHOLE. The board is one
%% fragment that the browser replaces when the house says something changed, and
%% the controls sit outside it and are never touched, so a swap arriving while
%% somebody is typing a quantity does not eat what they typed. That is why there
%% is one renderer here and not one here and another in JavaScript.
%%
%% NO DURATION IS EVER SHOWN FOR A PASSAGE. The page shows when a ship sailed,
%% when it is due, and how long is left. It does not show how long the crossing
%% takes and it must not, because that number is the sea's constant and
%% subtracting two of a port's own timestamps to recover it is exactly the leak
%% the contract puts an instant on the wire to prevent.
%%
%% Two vocabularies meet in the ticker and it is deliberate. An item that came
%% off the mesh carries the publisher's own payload, with binary keys, verbatim,
%% because the producer of a fact owns its content. An item this house wrote
%% about its own act has atom keys and is this house's own words. Each has its
%% own clause below and neither is translated into the other.
%% @end
-module(show_house_page).

-export([page/1, board/1]).
-export([money/1, quantity/1, price/1, clock/1, say/1]).

%% @doc The whole document. Served once; after that only the board moves.
-spec page(map()) -> iodata().
page(View) ->
    Names = maps:get(names, View),
    [<<"<!doctype html><html lang=\"en\"><head>">>,
     <<"<meta charset=\"utf-8\">">>,
     <<"<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">">>,
     <<"<title>">>, esc(tom_names:local(maps:get(ship, Names))),
     <<" &mdash; Traders of Macao</title>">>,
     <<"<style>">>, css(), <<"</style></head><body>">>,
     <<"<main>">>,
     masthead(Names),
     chart(),
     <<"<div id=\"board\">">>, board(View), <<"</div>">>,
     helm(Names),
     <<"</main><script>">>, script(), <<"</script></body></html>">>].

%% @doc Everything that moves. Swapped whole on every change.
-spec board(map()) -> iodata().
board(View) ->
    [voyage(maps:get(sight, View), maps:get(at, View)),
     topline(View),
     trouble(maps:get(trouble, View, #{})),
     hold(View),
     market(View),
     orders(maps:get(orders, View, [])),
     cash_book(maps:get(cash_book, View, #{})),
     news(maps:get(news, View, []))].

%%% Sections

%% THE CHART IS OUTSIDE THE SWAPPED FRAGMENT, for the same reason the helm is: a
%% board arriving every few seconds must not tear the picture out from under
%% somebody looking at it. What the board carries instead is the VOYAGE, as data
%% in a script tag, and the chart reads it after each swap and redraws.
%%
%% A script tag rather than a data attribute because a path is a hundred pairs of
%% numbers and that is not an attribute. It is never executed: the type is not
%% JavaScript, so a browser hands it over as text and nothing in it can run,
%% which matters because the line came off the mesh.
chart() ->
    <<"<section class=\"panel chart\"><h2>The chart</h2>"
      "<svg id=\"chart\" viewBox=\"0 0 1000 500\" "
      "preserveAspectRatio=\"xMidYMid meet\" role=\"img\" "
      "aria-label=\"Where the ship is\"></svg>"
      "<p class=\"sub\" id=\"chart-note\">&nbsp;</p></section>">>.

%% The voyage as the chart needs it, and nothing else: where the line goes, when
%% she left, when she is due. No duration, as everywhere else.
voyage(Sight, Now) ->
    [<<"<script type=\"application/json\" id=\"voyage\">">>,
     json:encode(drawn(maps:get(lane, Sight, undefined), Sight, Now)),
     <<"</script>">>].

%% THE ENDS COME OFF THE LANE AND NEVER OFF `where'. She moors, `where' becomes
%% the port she has arrived at, and the line still begins where she left: read
%% the label from one and the position from the other and the far port's name
%% lands on the near port's dot. Lisbon appeared in China for an afternoon.
drawn(undefined, Sight, Now) ->
    #{<<"standing">> => atom_to_binary(maps:get(standing, Sight), utf8),
      <<"path">> => [], <<"from">> => null, <<"to">> => null,
      <<"sailed_at">> => null, <<"due_at">> => null, <<"at">> => Now};
drawn(#{from := From, to := To, path := Path}, Sight, Now) ->
    #{<<"standing">> => atom_to_binary(maps:get(standing, Sight), utf8),
      <<"path">> => Path,
      <<"from">> => tom_names:local(From),
      <<"to">> => tom_names:local(To),
      <<"sailed_at">> => nullable(maps:get(sailed_at, Sight)),
      <<"due_at">> => nullable(maps:get(due_at, Sight)),
      <<"at">> => Now}.

nullable(undefined) -> null;
nullable(Value)     -> Value.


masthead(Names) ->
    [<<"<header><h1>">>, esc(tom_names:local(maps:get(ship, Names))), <<"</h1>">>,
     <<"<p class=\"sub\">">>, esc(tom_names:local(maps:get(house, Names))),
     <<"&rsquo;s house, trading out of ">>,
     port_list(maps:get(harbours, Names)), <<"</p></header>">>].

port_list(Harbours) ->
    join([esc(Local) || {Local, _MRI} <- Harbours], <<" and ">>).

topline(View) ->
    Sight = maps:get(sight, View),
    [<<"<section class=\"cards\">">>,
     card(<<"Purse">>, money(maps:get(purse, View)), <<>>),
     card(<<"Ship">>, standing(Sight, View), seen(Sight)),
     <<"</section>">>].

card(Title, Big, Sub) ->
    [<<"<div class=\"card\"><h2>">>, Title, <<"</h2><p class=\"big\">">>, Big,
     <<"</p><p class=\"sub\">">>, Sub, <<"</p></div>">>].

%% One sentence for where the hull is. Each clause is a state the world can
%% actually be in, including the two a player finds surprising: a landfall the
%% destination has not confirmed, and a house that has not asked anybody yet.
standing(#{standing := moored, where := Where}, _View) ->
    [<<"alongside at ">>, esc(tom_names:local(Where))];
standing(#{standing := in_passage, bound_for := Bound, due_at := Due}, View) ->
    [<<"at sea, bound for ">>, esc(tom_names:local(Bound)),
     <<"<br><span class=\"due\">due ">>, clock(Due), <<" &middot; ">>,
     countdown(Due, maps:get(at, View)), <<"</span>">>];
standing(#{standing := was_lost, cause := Cause, bound_for := Bound}, _View) ->
    [<<"<span class=\"bad\">lost to ">>, esc(cause(Cause)), <<"</span>">>,
     <<"<br><span class=\"due\">she was bound for ">>,
     esc(tom_names:local(Bound)), <<"</span>">>];
standing(#{standing := never_sailed}, _View) ->
    <<"never sailed, and no port is holding her">>;
standing(#{standing := unknown}, _View) ->
    <<"nobody asked yet">>.

cause(undefined) -> <<"something unrecorded">>;
cause(Cause)     -> Cause.

seen(#{sighted_at := undefined}) -> <<>>;
seen(#{sighted_at := At})        -> [<<"as she was at ">>, clock(At)].

hold(View) ->
    Cargo = maps:get(cargo, View, #{}),
    [<<"<section class=\"panel\"><h2>The hold</h2>">>,
     cargo_table(maps:to_list(Cargo)),
     <<"<p class=\"sub\">">>, quantity(maps:get(hold, View, 0.0)),
     <<" tons of hold, ">>, quantity(maps:get(free_hold, View, 0.0)),
     <<" free. There is no warehouse: a good is bought straight into the hold "
       "and sold straight out of it.</p></section>">>].

cargo_table([]) ->
    <<"<p class=\"empty\">Empty.</p>">>;
cargo_table(Cargo) ->
    [<<"<table><thead><tr><th>Good</th><th class=\"n\">Tons</th></tr></thead><tbody>">>,
     [[<<"<tr><td>">>, esc(tom_names:local(Good)), <<"</td><td class=\"n\">">>,
       quantity(Tons), <<"</td></tr>">>] || {Good, Tons} <- lists:sort(Cargo)],
     <<"</tbody></table>">>].

market(View) ->
    Names    = maps:get(names, View),
    Harbours = maps:get(harbours, Names),
    Quotes   = maps:get(quotes, View, #{}),
    [<<"<section class=\"panel\"><h2>The market</h2>">>,
     <<"<table><thead><tr><th>Good</th>">>,
     [[<<"<th class=\"n\">">>, esc(Local), <<" price</th><th class=\"n\">">>,
       esc(Local), <<" on the quay</th>">>] || {Local, _} <- Harbours],
     <<"</tr></thead><tbody>">>,
     [good_row(Good, Harbours, Quotes) || Good <- maps:get(goods, Names)],
     <<"</tbody></table>">>,
     freshness(Harbours, Quotes, maps:get(at, View)),
     <<"</section>">>].

good_row({Local, GoodMRI}, Harbours, Quotes) ->
    [<<"<tr><td>">>, esc(Local), <<"</td>">>,
     [cell(quote_for(GoodMRI, maps:get(MRI, Quotes, #{}))) || {_L, MRI} <- Harbours],
     <<"</tr>">>].

cell(undefined) ->
    <<"<td class=\"n empty\">&mdash;</td><td class=\"n empty\">&mdash;</td>">>;
cell(Quote) ->
    [<<"<td class=\"n\">">>, price(maps:get(<<"price">>, Quote, undefined)),
     <<"</td><td class=\"n\">">>, quantity(maps:get(<<"stock">>, Quote, undefined)),
     <<"</td>">>].

quote_for(GoodMRI, Posted) ->
    first_match([Q || Q <- maps:get(quotes, Posted, []),
                      maps:get(<<"good">>, Q, undefined) =:= GoodMRI]).

first_match([Q | _]) -> Q;
first_match([])      -> undefined.

freshness(Harbours, Quotes, Now) ->
    [<<"<p class=\"sub\">">>,
     join([[esc(Local), <<" ">>, age(maps:get(seen_at, maps:get(MRI, Quotes, #{}),
                                              undefined), Now)]
           || {Local, MRI} <- Harbours], <<", ">>),
     <<"</p>">>].

age(undefined, _Now) -> <<"never answered">>;
age(Seen, Now)       -> [<<"asked ">>, span(Now - Seen), <<" ago">>].

orders([]) ->
    <<"<section class=\"panel\"><h2>Orders</h2><p class=\"empty\">None yet.</p></section>">>;
orders(Orders) ->
    [<<"<section class=\"panel\"><h2>Orders</h2>">>,
     <<"<table><thead><tr><th>When</th><th>What</th><th>Good</th>">>,
     <<"<th class=\"n\">Tons</th><th>Port</th><th>How it went</th>">>,
     <<"<th class=\"n\">Coin</th></tr></thead><tbody>">>,
     [order_row(O) || O <- lists:sublist(Orders, 8)],
     <<"</tbody></table></section>">>].

order_row(Order) ->
    [<<"<tr class=\"o-">>, atom_to_binary(maps:get(state, Order), utf8), <<"\">">>,
     <<"<td>">>, clock(maps:get(at, Order)), <<"</td>">>,
     <<"<td>">>, kind(maps:get(kind, Order)), <<"</td>">>,
     <<"<td>">>, esc(tom_names:local(maps:get(good, Order))), <<"</td>">>,
     <<"<td class=\"n\">">>, quantity(tom_house:moved(Order)), <<"</td>">>,
     <<"<td>">>, esc(tom_names:local(maps:get(harbour, Order))), <<"</td>">>,
     <<"<td>">>, state(Order), <<"</td>">>,
     <<"<td class=\"n\">">>, coin(Order), <<"</td></tr>">>].

kind(purchase) -> <<"bought">>;
kind(sale)     -> <<"sold">>.

state(#{state := settled})              -> <<"done">>;
state(#{state := refused, reason := R}) -> [<<"refused. ">>, esc(say(R))];
state(#{state := ordered})              -> <<"still asking&hellip;">>.

coin(#{coin := Coin}) -> money(Coin);
coin(_Order)          -> <<"&mdash;">>.

%% THE ONE TABLE THAT ADDS UP. The orders table above is a log: newest first,
%% scanned for what became of a thing you asked for. This is an account: oldest
%% first, because a running balance means nothing except read downwards, and the
%% last balance in it is the purse arrived at by a different route than the card
%% at the top of the page.
cash_book(Book) when map_size(Book) =:= 0 ->
    <<>>;
cash_book(Book) ->
    {Opening, Shown} = window(maps:get(entries, Book, []),
                              maps:get(opened_with, Book, 0.0)),
    [<<"<section class=\"panel\"><h2>The cash book</h2>">>,
     <<"<table><thead><tr><th>When</th><th>What</th>">>,
     <<"<th class=\"n\">In</th><th class=\"n\">Out</th>">>,
     <<"<th class=\"n\">Balance</th></tr></thead><tbody>">>,
     Opening,
     [book_row(E) || E <- Shown],
     <<"</tbody></table>">>,
     <<"<p class=\"sub\">Only a settlement moves money. An order still open has "
       "committed nothing and a refusal cost nothing, so neither is here.</p>">>,
     <<"</section>">>].

%% The last eight movements, and when there are more the book opens with what
%% was brought forward rather than with the genesis purse. Keeping the opening
%% balance above a window that dropped the earlier rows would print a column
%% that does not add up, which is the one thing a cash book may not do.
window(Entries, Opened) when length(Entries) =< 8 ->
    {opening(<<"The house opened">>, Opened), Entries};
window(Entries, _Opened) ->
    {Earlier, Kept} = lists:split(length(Entries) - 8, Entries),
    {opening(<<"Brought forward">>, maps:get(balance, lists:last(Earlier))), Kept}.

opening(What, Balance) ->
    [<<"<tr class=\"o-opening\"><td>&mdash;</td><td>">>, What,
     <<"</td><td class=\"n empty\">&mdash;</td><td class=\"n empty\">&mdash;</td>">>,
     <<"<td class=\"n\">">>, money(Balance), <<"</td></tr>">>].

book_row(Entry) ->
    Kind = maps:get(kind, Entry),
    [<<"<tr><td>">>, clock(maps:get(at, Entry)), <<"</td><td>">>,
     movement(Kind, Entry), <<"</td>">>,
     money_in(Kind, Entry), money_out(Kind, Entry),
     <<"<td class=\"n\">">>, money(maps:get(balance, Entry)), <<"</td></tr>">>].

movement(purchase, E) ->
    [<<"Bought ">>, quantity(maps:get(tons, E)), <<" of ">>,
     esc(tom_names:local(maps:get(good, E))), <<" at ">>,
     esc(tom_names:local(maps:get(harbour, E)))];
movement(sale, E) ->
    [<<"Sold ">>, quantity(maps:get(tons, E)), <<" of ">>,
     esc(tom_names:local(maps:get(good, E))), <<" at ">>,
     esc(tom_names:local(maps:get(harbour, E)))].

%% A column carries a number only when the money went that way. A zero in the
%% other one reads as a movement of nothing, which is not what happened.
money_in(sale, E)       -> [<<"<td class=\"n\">">>, money(maps:get(coin, E)), <<"</td>">>];
money_in(_Kind, _E)     -> <<"<td class=\"n empty\">&mdash;</td>">>.

money_out(purchase, E)  -> [<<"<td class=\"n\">">>, money(maps:get(coin, E)), <<"</td>">>];
money_out(_Kind, _E)    -> <<"<td class=\"n empty\">&mdash;</td>">>.

news([]) ->
    <<>>;
news(Items) ->
    [<<"<section class=\"panel\"><h2>The word on the quay</h2><ul class=\"news\">">>,
     [[<<"<li><time>">>, clock(maps:get(at, I)), <<"</time> ">>,
       item(maps:get(fact, I), maps:get(payload, I)), <<"</li>">>] || I <- Items],
     <<"</ul></section>">>].

%% This house's own acts. Atom keys, because these are its own words.
item(you_bought, #{good := G, harbour := H, quantity := Q, coin := C}) ->
    [<<"You bought ">>, quantity(Q), <<" of ">>, esc(tom_names:local(G)),
     <<" at ">>, esc(tom_names:local(H)), <<" for ">>, money(C), <<".">>];
item(you_sold, #{good := G, harbour := H, quantity := Q, coin := C}) ->
    [<<"You sold ">>, quantity(Q), <<" of ">>, esc(tom_names:local(G)),
     <<" at ">>, esc(tom_names:local(H)), <<" for ">>, money(C), <<".">>];
item(you_sailed, #{from := F, bound_for := B}) ->
    [<<"You sent her out of ">>, esc(tom_names:local(F)), <<", bound for ">>,
     esc(tom_names:local(B)), <<".">>];
%% Facts off the mesh. Binary keys, the publisher's own payload, verbatim.
item(cargo_loaded, P) ->
    [<<"Loaded ">>, quantity(maps:get(<<"quantity">>, P, undefined)), <<" of ">>,
     esc(tom_names:local(maps:get(<<"good">>, P, <<"?">>))), <<" at ">>,
     esc(tom_names:local(maps:get(<<"harbour">>, P, <<"?">>))), <<".">>];
item(cargo_discharged, P) ->
    [<<"Discharged ">>, quantity(maps:get(<<"quantity">>, P, undefined)), <<" of ">>,
     esc(tom_names:local(maps:get(<<"good">>, P, <<"?">>))), <<" at ">>,
     esc(tom_names:local(maps:get(<<"harbour">>, P, <<"?">>))), <<".">>];
item(ship_moored, P) ->
    [<<"She is alongside at ">>,
     esc(tom_names:local(maps:get(<<"harbour">>, P, <<"?">>))), <<".">>];
item(ship_sailed, P) ->
    [<<"She sailed for ">>,
     esc(tom_names:local(maps:get(<<"bound_for">>, P, <<"?">>))), <<", due ">>,
     clock(maps:get(<<"due_at">>, P, undefined)), <<".">>];
item(landfall_made, P) ->
    [<<"She made landfall at ">>,
     esc(tom_names:local(maps:get(<<"bound_for">>, P, <<"?">>))), <<".">>];
item(ship_lost, P) ->
    [<<"<span class=\"bad\">She was lost to ">>,
     esc(cause(maps:get(<<"cause">>, P, undefined))), <<"</span>, bound for ">>,
     esc(tom_names:local(maps:get(<<"bound_for">>, P, <<"?">>))), <<".">>];
item(Fact, Payload) ->
    [esc(atom_to_binary(Fact, utf8)), <<": ">>, esc(reason(Payload))].

trouble(Trouble) when map_size(Trouble) =:= 0 ->
    <<>>;
trouble(Trouble) ->
    [<<"<section class=\"panel warn\"><h2>Not everything answered</h2><ul>">>,
     [[<<"<li><strong>">>, esc(atom_to_binary(Where, utf8)), <<"</strong> ">>,
       esc(reason(maps:get(reason, What))), <<" <time>">>,
       clock(maps:get(at, What)), <<"</time></li>">>]
      || {Where, What} <- lists:sort(maps:to_list(Trouble))],
     <<"</ul></section>">>].

%%% The controls. Static: nothing here is ever swapped, so nothing here can eat
%%% what the player is halfway through typing.

helm(Names) ->
    [<<"<section class=\"helm\"><h2>The helm</h2>">>,
     <<"<p id=\"outcome\" class=\"outcome\">&nbsp;</p>">>,
     <<"<form class=\"act\" method=\"post\" action=\"/act\">">>,
     <<"<label for=\"good\">Good</label><select id=\"good\" name=\"good\">">>,
     [[<<"<option value=\"">>, esc(Local), <<"\">">>, esc(Local), <<"</option>">>]
      || {Local, _MRI} <- maps:get(goods, Names)],
     <<"</select>">>,
     <<"<label for=\"quantity\">Tons</label>">>,
     <<"<input id=\"quantity\" name=\"quantity\" type=\"number\" "
       "min=\"0.1\" step=\"0.1\" value=\"10\">">>,
     <<"<button name=\"do\" value=\"quote\">What would it cost?</button>">>,
     <<"<button name=\"do\" value=\"buy\" class=\"go\">Buy into the hold</button>">>,
     <<"<button name=\"do\" value=\"sell\" class=\"go\">Sell out of the hold</button>">>,
     <<"</form>">>,
     <<"<form class=\"act\" method=\"post\" action=\"/act\">">>,
     <<"<label for=\"bound_for\">Sail for</label>">>,
     <<"<select id=\"bound_for\" name=\"bound_for\">">>,
     [[<<"<option value=\"">>, esc(Local), <<"\">">>, esc(Local), <<"</option>">>]
      || {Local, _MRI} <- maps:get(harbours, Names)],
     <<"</select>">>,
     <<"<button name=\"do\" value=\"sail\" class=\"go\">Cast off</button>">>,
     <<"<button name=\"do\" value=\"ask\">Ask everybody where she is</button>">>,
     <<"</form></section>">>].

%%% Saying it in English
%%%
%%% Everything below this point in the house speaks in Erlang terms, because
%%% that is what the mesh and the aggregate deal in, and everything above it is
%%% a person. This is where the two meet, and it is the only place they do.

%% @doc Turn one reason into a sentence somebody can act on.
%%
%% Exported and tested, because a page that says `{error,{call_error,15,...}}'
%% to a player has failed whatever the rest of the tests say.
-spec say(term()) -> binary().
say({ship_is_not_alongside, Standing}) ->
    <<"She is not lying at a port. ", (where_she_is(Standing))/binary>>;
say({not_enough_coin, Coin}) ->
    <<"That would cost ", (iolist_to_binary(money(Coin)))/binary,
      " and the purse will not stretch that far.">>;
say({already_there, Where}) ->
    <<"She is already at ", (tom_names:local(Where))/binary, ".">>;
say({not_a_harbour, _Name}) ->
    <<"That is not the name of a harbour.">>;
say({quote_without_a_price, _Quote}) ->
    <<"The port answered without a price in it.">>;
say({receipt_without_a_price, _Receipt}) ->
    <<"The port sent a receipt with no price in it. The order stays open and "
      "the house will keep asking.">>;
say({unknown_good, _Name}) ->
    <<"This house does not trade that.">>;
say({bad_quantity, _Given}) ->
    <<"That is not a number of tons.">>;
say(no_mesh) ->
    <<"Not on the mesh yet. The house dials out and keeps trying.">>;
%% The enumerated reasons, as a port sends them. They arrive whole because a
%% refusal travels as a reply with the reason inside it rather than as
%% `{error, Reason}', whose reason the mesh drops on the floor.
say(<<"unknown_good">>) ->
    <<"That port does not trade this.">>;
say(<<"quay_empty">>) ->
    <<"There is none of it on the quay.">>;
say(<<"godown_full">>) ->
    <<"The godown will not take any more of it.">>;
say(<<"hold_full">>) ->
    <<"She has not the room. Sell something first, or buy less.">>;
say(<<"not_in_hold">>) ->
    <<"There is none of that aboard.">>;
say(<<"not_here">>) ->
    <<"That port is not holding her.">>;
say(<<"not_yours">>) ->
    <<"She is not this house's ship.">>;
say(<<"ship_consigned">>) ->
    <<"She is promised away and frozen. Nothing can be loaded or sold until "
      "she is taken.">>;
say(<<"bad_destination">>) ->
    <<"That is not the name of a harbour.">>;
say(<<"already_bound">>) ->
    <<"She is already bound somewhere else.">>;
say(<<"bad_quantity">>) ->
    <<"That is not a number of tons.">>;
say(Reason) when is_binary(Reason) ->
    <<"The port said no: ", Reason/binary, ".">>;
%% Since macula 8.0.0 a refusal carries its reason, so this is now only reached
%% when the far side is too old to send one. Left in because a port on an older
%% SDK should still get a sentence rather than a tuple.
say({call_error, 16#0F, _Name}) ->
    <<"The port said no, and did not say why. That port is running an older "
      "mesh than this house.">>;
say({call_error, _Code, _Name}) ->
    <<"The port could not be reached just now.">>;
say(timeout) ->
    <<"Nobody answered in time.">>;
say(Other) ->
    iolist_to_binary(io_lib:format("~0p", [Other])).

%% Everything else in this game is written in careful English, and this one
%% clause used to print the standing atom straight into a sentence: "She is
%% was_lost." A player should never be shown the inside of the machine.
where_she_is(in_passage)     -> <<"She is at sea.">>;
where_she_is(was_lost)       -> <<"She is lost.">>;
where_she_is(never_sailed)   -> <<"She has never sailed.">>;
where_she_is(_Not_yet_known) -> <<"Where she is is not known just now.">>.

%%% Formatting

%% @doc Coin, to the nearest hundredth. Money is shown at one precision
%% everywhere so two numbers on a page can be compared by eye.
-spec money(number() | undefined) -> iodata().
money(undefined) -> <<"&mdash;">>;
money(N)         -> io_lib:format("~.2f", [float(N)]).

%% @doc A price, at the precision the market actually moves in. Two decimals
%% would round away the difference a small trade makes, which is the difference a
%% player is looking at.
-spec price(number() | undefined) -> iodata().
price(undefined) -> <<"&mdash;">>;
price(N)         -> io_lib:format("~.4f", [float(N)]).

%% @doc Tons, without a train of zeroes behind a whole number.
-spec quantity(number() | undefined) -> iodata().
quantity(undefined)             -> <<"&mdash;">>;
quantity(N) when is_integer(N)  -> integer_to_binary(N);
quantity(N) when is_float(N)    -> shorten(iolist_to_binary(io_lib:format("~.3f", [N]))).

shorten(Bin) -> unpad(binary:split(Bin, <<".">>), Bin).

unpad([Whole, Frac], _Bin) -> rejoin(Whole, trim_zeroes(Frac));
unpad(_Other, Bin)         -> Bin.

rejoin(Whole, <<>>)  -> Whole;
rejoin(Whole, Frac)  -> <<Whole/binary, ".", Frac/binary>>.

trim_zeroes(<<>>) -> <<>>;
trim_zeroes(Frac) -> lopped(binary:last(Frac), Frac).

lopped($0, Frac) -> trim_zeroes(binary:part(Frac, 0, byte_size(Frac) - 1));
lopped(_, Frac)  -> Frac.

%% @doc An instant, as a wall clock in the reader's own timezone.
-spec clock(integer() | undefined) -> iodata().
clock(undefined) ->
    <<"&mdash;">>;
clock(Ms) when is_integer(Ms) ->
    {_Date, {H, M, S}} = calendar:system_time_to_local_time(Ms, millisecond),
    io_lib:format("~2..0b:~2..0b:~2..0b", [H, M, S]).

%% A duration in words. Only ever used for "how long ago" and "how long left",
%% never for how long a crossing takes.
span(Ms) when Ms < 1000     -> <<"a moment">>;
span(Ms) when Ms < 60_000   -> [integer_to_binary(Ms div 1000), <<"s">>];
span(Ms)                    -> [integer_to_binary(Ms div 60_000), <<"m ">>,
                                integer_to_binary((Ms rem 60_000) div 1000), <<"s">>].

countdown(undefined, _Now) ->
    <<>>;
countdown(Due, Now) ->
    Left = Due - Now,
    [<<"<span class=\"countdown\" data-left=\"">>, integer_to_binary(Left),
     <<"\">">>, remaining(Left), <<"</span>">>].

remaining(Left) when Left =< 0 -> <<"any moment now">>;
remaining(Left)                -> [span(Left), <<" to go">>].

%% Anything that came out of an error tuple. Rendered with ~p because it is an
%% Erlang term and pretending otherwise loses what it says.
reason(R) when is_binary(R) -> R;
reason(R)                   -> iolist_to_binary(io_lib:format("~0p", [R])).

join([], _Sep)      -> [];
join([One], _Sep)   -> [One];
join([H | T], Sep)  -> [H, Sep, join(T, Sep)].

%% Everything that reaches the page from off this machine goes through here.
esc(Bin) when is_binary(Bin) ->
    << <<(escaped(C))/binary>> || <<C>> <= Bin >>;
esc(Other) ->
    esc(iolist_to_binary(io_lib:format("~0p", [Other]))).

escaped($&) -> <<"&amp;">>;
escaped($<) -> <<"&lt;">>;
escaped($>) -> <<"&gt;">>;
escaped($") -> <<"&quot;">>;
escaped($') -> <<"&#39;">>;
escaped(C)  -> <<C>>.

%%% Chrome

css() ->
    <<"*{box-sizing:border-box}"
      ":root{--ink:#1b1a17;--dim:#6b6558;--paper:#f6f1e6;--card:#fffdf7;"
      "--line:#ddd3bd;--go:#1f5c3a;--bad:#8c2f18;--warn:#7a5c12;"
      "--sea:#dce6ea;--land:#efe7d4;--coast:#c3b79b}"
      "@media(prefers-color-scheme:dark){:root{--ink:#ece5d6;--dim:#9a9384;"
      "--paper:#16150f;--card:#1f1d16;--line:#3a362a;--go:#2f7d52;"
      "--bad:#e2765a;--warn:#d8b34a;"
      "--sea:#101821;--land:#241f16;--coast:#3d3628}}"
      "body{margin:0;background:var(--paper);color:var(--ink);"
      "font:16px/1.5 ui-serif,Georgia,'Times New Roman',serif}"
      "main{max-width:66rem;margin:0 auto;padding:1.5rem 1rem 4rem}"
      "header{border-bottom:2px solid var(--line);padding-bottom:.5rem;"
      "margin-bottom:1.25rem}"
      "h1{font-size:2rem;margin:0;letter-spacing:.02em}"
      "h2{font-size:.8rem;text-transform:uppercase;letter-spacing:.12em;"
      "color:var(--dim);margin:0 0 .5rem;font-weight:600;"
      "font-family:ui-sans-serif,system-ui,sans-serif}"
      ".sub{color:var(--dim);font-size:.9rem;margin:.25rem 0 0}"
      ".cards{display:flex;gap:1rem;flex-wrap:wrap;margin-bottom:1rem}"
      ".card{flex:1 1 16rem;background:var(--card);border:1px solid var(--line);"
      "border-radius:.4rem;padding:.9rem 1rem}"
      ".big{font-size:1.5rem;margin:0;font-variant-numeric:tabular-nums}"
      ".panel{background:var(--card);border:1px solid var(--line);"
      "border-radius:.4rem;padding:.9rem 1rem;margin-bottom:1rem}"
      ".panel.warn{border-color:var(--warn)}"
      ".panel.warn h2{color:var(--warn)}"
      "table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}"
      "th,td{text-align:left;padding:.35rem .5rem;border-bottom:1px solid var(--line)}"
      "th{font:600 .75rem/1.4 ui-sans-serif,system-ui,sans-serif;"
      "text-transform:uppercase;letter-spacing:.06em;color:var(--dim)}"
      "td.n,th.n{text-align:right}"
      "tbody tr:last-child td{border-bottom:none}"
      ".empty{color:var(--dim)}"
      ".bad{color:var(--bad);font-weight:600}"
      ".due{color:var(--dim);font-size:.95rem}"
      ".news{list-style:none;margin:0;padding:0}"
      ".news li{padding:.25rem 0;border-bottom:1px dotted var(--line)}"
      ".news li:last-child{border-bottom:none}"
      "time{color:var(--dim);font-variant-numeric:tabular-nums;"
      "font-size:.85rem;margin-right:.4rem}"
      ".o-refused td{color:var(--bad)}"
      ".o-ordered td{color:var(--warn)}"
      ".o-opening td{color:var(--dim);font-style:italic}"
      ".chart{padding:0;overflow:hidden}"
      ".chart h2{padding:.9rem 1rem 0}"
      "#chart{display:block;width:100%;height:auto;background:var(--sea)}"
      "#chart .land{fill:var(--land);stroke:var(--coast);stroke-width:.5}"
      "#chart .lane{fill:none;stroke:var(--ink);stroke-width:2;"
      "stroke-dasharray:5 4;opacity:.5}"
      "#chart .sailed{fill:none;stroke:var(--go);stroke-width:2.5;opacity:.9}"
      "#chart .port{fill:var(--ink)}"
      "#chart .ship{fill:var(--go);stroke:var(--paper);stroke-width:1.5}"
      "#chart .wreck{fill:var(--bad)}"
      "#chart text{font:600 13px ui-sans-serif,system-ui,sans-serif;"
      "fill:var(--ink)}"
      "#chart-note{padding:0 1rem .9rem;margin:.4rem 0 0}"
      ".helm{position:sticky;bottom:0;background:var(--card);"
      "border:1px solid var(--line);border-radius:.4rem;padding:.9rem 1rem;"
      "box-shadow:0 -.4rem 1.2rem rgba(0,0,0,.08)}"
      ".helm form{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap;"
      "margin:0 0 .5rem}"
      ".helm label{font:600 .75rem/1 ui-sans-serif,system-ui,sans-serif;"
      "text-transform:uppercase;letter-spacing:.06em;color:var(--dim)}"
      "select,input,button{font:inherit;padding:.4rem .6rem;border-radius:.3rem;"
      "border:1px solid var(--line);background:var(--paper);color:var(--ink)}"
      "input{width:7rem;text-align:right}"
      "button{cursor:pointer}"
      "button.go{background:var(--go);border-color:var(--go);color:var(--paper);"
      "font-weight:600}"
      "button[disabled]{opacity:.5;cursor:progress}"
      ".outcome{margin:0 0 .6rem;min-height:1.5rem;font-weight:600}"
      ".outcome.bad{color:var(--bad)}">>.

script() ->
    <<"var t0=Date.now();\n"
      "function ticks(){var n=Date.now();"
      "document.querySelectorAll('.countdown').forEach(function(c){"
      "var left=parseInt(c.dataset.left,10)-(n-t0);"
      "c.textContent=left<=0?'any moment now':words(left)+' to go';});}\n"
      "function words(ms){var s=Math.floor(ms/1000);"
      "return s<60?s+'s':Math.floor(s/60)+'m '+(s%60)+'s';}\n"
      "setInterval(ticks,1000);\n"
      "var src=new EventSource('/stream');\n"
      "src.addEventListener('board',function(e){"
      "document.getElementById('board').innerHTML=JSON.parse(e.data);"
      "t0=Date.now();ticks();drawChart();});\n"
      "\n"
      "/* THE CHART. Equirectangular, which is what a period chart is: a\n"
      " * rectangle of latitude against longitude. It is wrong about area at the\n"
      " * poles and this trade never goes there.\n"
      " *\n"
      " * The window is the voyage, not the world. It frames the line she is on\n"
      " * with a margin, so a hop through the Formosa Strait fills the panel just\n"
      " * as the galleon does, and the land is drawn three times, at minus, plus\n"
      " * and no offset of a full turn, because the galleon's longitude runs past\n"
      " * 180 and the coastline does not. The viewBox throws away what misses. */\n"
      "var COAST=null;\n"
      "function chartLand(){return fetch('/coastline').then(function(r){"
      "return r.json();}).then(function(c){COAST=c;});}\n"
      "function voyage(){var el=document.getElementById('voyage');"
      "try{return el?JSON.parse(el.textContent):null;}catch(e){return null;}}\n"
      "function drawChart(){"
      "var svg=document.getElementById('chart'),v=voyage();"
      "if(!svg||!v)return;"
      "var note=document.getElementById('chart-note');"
      "var p=v.path||[];"
      "if(p.length<2){svg.innerHTML='';"
      "note.textContent=v.standing==='moored'?'She is alongside. Cast off to put a line on the water.':'No line to draw yet.';"
      "return;}"
      "var W=1000,H=500,M=40;"
      "var lats=p.map(function(q){return q[0];}),lngs=p.map(function(q){return q[1];});"
      "var la0=Math.min.apply(null,lats),la1=Math.max.apply(null,lats);"
      "var lo0=Math.min.apply(null,lngs),lo1=Math.max.apply(null,lngs);"
      "var pad=Math.max((la1-la0),(lo1-lo0))*0.12+2;"
      "la0-=pad;la1+=pad;lo0-=pad;lo1+=pad;"
      %% Degrees of longitude are shorter away from the equator, so the
      %% window is squeezed by the cosine of its own middle latitude or
      %% the Cape comes out stretched.
      "var mid=(la0+la1)/2,k=Math.cos(mid*Math.PI/180)||1;"
      "var spanX=(lo1-lo0)*k,spanY=(la1-la0);"
      "var s=Math.min((W-2*M)/spanX,(H-2*M)/spanY);"
      "var cx=(lo0+lo1)/2,cy=(la0+la1)/2;"
      "function X(lng){return W/2+(lng-cx)*k*s;}"
      "function Y(lat){return H/2-(lat-cy)*s;}"
      "function line(pts){return pts.map(function(q,i){"
      "return (i?'L':'M')+X(q[1]).toFixed(1)+' '+Y(q[0]).toFixed(1);}).join('');}\n"
      "var out=[];"
      "if(COAST){[-360,0,360].forEach(function(off){COAST.forEach(function(ring){"
      "var d=ring.map(function(q,i){"
      "return (i?'L':'M')+X(q[0]+off).toFixed(1)+' '+Y(q[1]).toFixed(1);}).join('')+'Z';"
      "out.push('<path class=\"land\" d=\"'+d+'\"/>');});});}"
      "out.push('<path class=\"lane\" d=\"'+line(p)+'\"/>');\n"
      %% How far along she is, from two instants and this browser's own
      %% clock. No duration came over the wire and none is derived here.
      "var t=0;"
      "if(v.sailed_at&&v.due_at&&v.due_at>v.sailed_at){"
      "t=(Date.now()-v.sailed_at)/(v.due_at-v.sailed_at);"
      "t=Math.max(0,Math.min(1,t));}"
      "if(v.standing!=='in_passage')t=(v.standing==='moored')?1:t;"
      "var seg=[],walked=0,total=0,d2=[];"
      "for(var i=1;i<p.length;i++){var dx=(p[i][1]-p[i-1][1])*k,dy=p[i][0]-p[i-1][0];"
      "var L=Math.hypot(dx,dy);d2.push(L);total+=L;}"
      "var want=total*t,at=p[0];"
      "for(var j=0;j<d2.length;j++){"
      "if(walked+d2[j]>=want){var f=d2[j]?(want-walked)/d2[j]:0;"
      "at=[p[j][0]+(p[j+1][0]-p[j][0])*f,p[j][1]+(p[j+1][1]-p[j][1])*f];"
      "seg=p.slice(0,j+1).concat([at]);break;}"
      "walked+=d2[j];seg=p.slice(0,j+2);at=p[j+1];}"
      "if(seg.length>1)out.push('<path class=\"sailed\" d=\"'+line(seg)+'\"/>');\n"
      "function dot(q,cls,label,dx){"
      "out.push('<circle class=\"'+cls+'\" cx=\"'+X(q[1]).toFixed(1)+'\" cy=\"'+Y(q[0]).toFixed(1)+'\" r=\"4\"/>');"
      "if(label)out.push('<text x=\"'+(X(q[1])+dx).toFixed(1)+'\" y=\"'+(Y(q[0])-8).toFixed(1)+'\" text-anchor=\"'+(dx<0?'end':'start')+'\">'+label+'</text>');}"
      "dot(p[0],'port',v.from||'',6);dot(p[p.length-1],'port',v.to||'',-6);"
      "if(v.standing==='was_lost'){"
      "out.push('<path class=\"wreck\" transform=\"translate('+X(at[1]).toFixed(1)+','+Y(at[0]).toFixed(1)+')\" d=\"M-6-6L6 6M-6 6L6-6\" stroke=\"currentColor\" stroke-width=\"3\"/>');}"
      "else if(v.standing==='in_passage'){"
      "out.push('<circle class=\"ship\" cx=\"'+X(at[1]).toFixed(1)+'\" cy=\"'+Y(at[0]).toFixed(1)+'\" r=\"6\"/>');}"
      "svg.innerHTML=out.join('');"
      "note.textContent=v.standing==='in_passage'"
      "?'Her line, and where she has got to.':"
      "(v.standing==='was_lost'?'Where she was lost.':'The water she last crossed.');}\n"
      "chartLand().then(drawChart).catch(drawChart);"
      "setInterval(function(){var v=voyage();if(v&&v.standing==='in_passage')drawChart();},1000);\n"
      "document.querySelectorAll('form.act').forEach(function(f){"
      "f.addEventListener('submit',function(ev){ev.preventDefault();"
      "var body=new URLSearchParams(new FormData(f));"
      "if(ev.submitter&&ev.submitter.name){body.set(ev.submitter.name,ev.submitter.value);}"
      "var out=document.getElementById('outcome');"
      "var btns=f.querySelectorAll('button');"
      "btns.forEach(function(b){b.disabled=true;});"
      "out.className='outcome';out.textContent='asking\\u2026';"
      "fetch('/act',{method:'POST',headers:{'accept':'application/json',"
      "'content-type':'application/x-www-form-urlencoded'},body:body})"
      ".then(function(r){return r.json();})"
      ".then(function(j){out.textContent=j.message;"
      "out.className=j.ok?'outcome':'outcome bad';})"
      ".catch(function(err){out.textContent=String(err);"
      "out.className='outcome bad';})"
      ".then(function(){btns.forEach(function(b){b.disabled=false;});});});});\n">>.
