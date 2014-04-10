-module(gracerl).

-behaviour(application).

%% Application callbacks
-export([start/0, start/2,
         stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start() ->
    application:start(tracerl),
    application:start(gracerl).

start(_StartType, _StartArgs) ->
    gracerl_sup:start_link().

stop(_State) ->
    ok.
