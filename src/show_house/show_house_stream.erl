%% @doc The page keeps up without anybody pressing anything.
%%
%% A server-sent-events stream. The house pushes one rendered board per change
%% and the browser swaps it in. That is why there is exactly one renderer, in
%% Erlang, rather than one here and a second copy of it in JavaScript that
%% disagrees with it by Thursday.
%%
%% THE BOARD IS SENT AS A JSON STRING, not as raw HTML. An SSE frame is
%% line-oriented and a newline inside a payload ends the event, so a rendered
%% page put on the wire unescaped arrives as a dozen truncated events. Encoding
%% it as one JSON string escapes every newline for free, and the browser undoes
%% it in one call.
%%
%% The heartbeat is a comment line every twenty seconds. Without it a proxy or a
%% laptop's power management quietly drops an idle connection, and the page stops
%% updating without anything looking wrong. EventSource reconnects on its own
%% when the socket really does die, which is the whole reason this is SSE and not
%% a socket somebody has to babysit.
%% @end
-module(show_house_stream).

-export([init/2, info/3, terminate/3]).

-define(HEARTBEAT_MS, 20_000).

init(Req0, State) ->
    Req = cowboy_req:stream_reply(
            200,
            #{<<"content-type">>  => <<"text/event-stream">>,
              <<"cache-control">> => <<"no-store">>},
            Req0),
    ok = keep_house:watch(self()),
    ok = board(keep_house:snapshot(), Req),
    _ = erlang:send_after(?HEARTBEAT_MS, self(), beat),
    {cowboy_loop, Req, State}.

info({house_changed, View}, Req, State) ->
    ok = board(View, Req),
    {ok, Req, State};
info(beat, Req, State) ->
    ok = cowboy_req:stream_body(<<": still here\n\n">>, nofin, Req),
    _ = erlang:send_after(?HEARTBEAT_MS, self(), beat),
    {ok, Req, State};
info(_Other, Req, State) ->
    {ok, Req, State}.

terminate(_Reason, _Req, _State) -> ok.

%%% Internal

board(View, Req) ->
    Html = json:encode(iolist_to_binary(show_house_page:board(View))),
    cowboy_req:stream_body([<<"event: board\ndata: ">>, Html, <<"\n\n">>], nofin, Req).
