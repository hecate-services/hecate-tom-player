%% @doc The page a human looks at, and the same thing as JSON for anyone who
%% would rather curl it.
%%
%% Four routes, and only one of them is for a browser:
%%
%%   GET  /        the page
%%   GET  /view    the same snapshot as JSON, for a shell
%%   GET  /stream  server-sent events, one rendered board per change
%%   POST /act     buy, sell, sail, price, or ask again
%%
%% This listener is the house's OWN, on its own port, beside the one hecate_om
%% runs for /health. They are separate because they answer to different people:
%% /health answers to whatever supervises the container and must stay boring,
%% and this answers to a player.
%% @end
-module(show_house).

-export([routes/0, init/2]).

-spec routes() -> [{string(), module(), term()}].
routes() ->
    [{"/", ?MODULE, page},
     {"/view", ?MODULE, view},
     {"/stream", show_house_stream, []},
     {"/act", show_house_act, []}].

init(Req0, page) ->
    Body = show_house_page:page(keep_house:snapshot()),
    {ok, sent(<<"text/html; charset=utf-8">>, Body, Req0), page};
init(Req0, view) ->
    Body = json:encode(show_house_json:snapshot(keep_house:snapshot())),
    {ok, sent(<<"application/json">>, Body, Req0), view}.

%%% Internal

%% Nothing here is cacheable. A price four seconds old shown as though it were
%% now is worse than no price, and a browser that helpfully remembers a purse is
%% a browser lying to a player about their money.
sent(Type, Body, Req) ->
    cowboy_req:reply(200,
                     #{<<"content-type">>  => Type,
                       <<"cache-control">> => <<"no-store">>},
                     Body, Req).
