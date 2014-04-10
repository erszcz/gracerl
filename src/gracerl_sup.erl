-module(gracerl_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    CarbonHost = application:get_env(gracerl, carbon_host, "localhost"),
    CarbonPort = application:get_env(gracerl, carbon_port, 2003),
    supervisor:start_link({local, ?MODULE}, ?MODULE, [CarbonHost, CarbonPort]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([CarbonHost, CarbonPort]) ->
    Procs = [{gracerl_server,
              {gracerl_server, start_link, []},
              permanent, 1000, worker, [gracerl_server]},
             {carbonizer,
              {carbonizer, start_link, [CarbonHost, CarbonPort,
                                        [{register, {local, carbonizer}}]]},
              permanent, 1000, worker, [carbonizer]}],
    {ok, {{one_for_one, 5, 10}, Procs}}.
