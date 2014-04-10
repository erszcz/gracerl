-module(gracerl_server).

-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).
-define(cfg(K), begin {ok, V} = application:get_env(gracerl, K), V end).

-record(state, {trace_pid}).

-define(l2b(L), list_to_binary(L)).
-define(l2i(L), list_to_integer(L)).
-define(a2l(A), atom_to_list(A)).
-define(a2b(A), ?l2b(?a2l(A))).
-define(b2l(A), binary_to_list(A)).

-include_lib("carbonizer/include/carbonizer.hrl").

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:cast(?SERVER, stop).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    Handler = fun(Msg) -> gen_server:cast(?SERVER, {trace, self(), Msg}) end,
    {ok, TracePid} = tracerl:start_trace(script_src(), ?cfg(node),
                                         Handler, [term]),
    {ok, #state{trace_pid = TracePid}}.

%handle_call(add, {Pid, _Ref}, State = #state{sockets = Sockets}) ->
%    Reply = ok,
%    {reply, Reply, State#state{sockets = [Pid|Sockets]}};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({send, Sample}, #state{} = State) ->
    carbonizer:send(Sample),
    {noreply, State};
handle_cast({trace, TP, {term, Term}}, State = #state{trace_pid = TP}) ->
    handle_term(Term),
    {noreply, State};
handle_cast({trace, TP, {error, Reason, Line}},
            State = #state{trace_pid = TP}) ->
    error_logger:error_report({error, Reason, Line}),
    {noreply, State};
handle_cast({trace, TP, eof}, State = #state{trace_pid = TP}) ->
    {stop, normal, State};
handle_cast(stop, State = #state{trace_pid = TP}) ->
    tracerl:stop(TP),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_term(Term) ->
    Timestamp = os:timestamp(),
    Samples = term_to_samples(Term),
    io:format("term: ~p~n~n", [Term]),
    io:format("samples: ~p~n", [Samples]),
    [gen_server:cast(?SERVER, {send, S#carbon_sample{timestamp = Timestamp}})
     || S <- Samples].

term_to_samples(Term) ->
    lists:flatmap(fun subterm_to_samples/1, Term).

%% TODO: term: [{sent,[stat,{"<0.129.0>","<0.130.0>",0,5}]}

subterm_to_samples({Stat, [stat | Pids]})
  when spawned =:= Stat;
       exited =:= Stat ->
    %% TODO: this is broken, as the same high value will presist on the graph,
    %%       though in fact it may have been zeroed already.
    %%       otoh, it's not wise to send a 0 every time,
    %%       only when a change happens - a memory of previous values might be
    %%       needed
    case Pids of
        [] -> [];
        _ ->
            [sample(metric(?cfg(node), Stat), length(Pids))]
    end;
subterm_to_samples({Stat, [stat | PidSent]})
  when queued =:= Stat;
       received =:= Stat;
       sent_self =:= Stat;
       sent_total =:= Stat ->
    series_to_samples(metric(?cfg(node), Stat), PidSent);
subterm_to_samples(_) ->
    [].

sample(Metric, Value) ->
    #carbon_sample{metric = Metric, value = Value}.

-spec metric(node(), atom()) -> iolist().
metric(Node, Stat) ->
    [<<"nodes">>, $., ?a2b(Node), $., ?a2b(Stat)].

-type series() :: [{string(), integer()}].

-spec series_to_samples(iolist(), series()) -> [carbon_sample()].
series_to_samples(Metric, Series) ->
    [#carbon_sample{metric = [Metric, $., normalise(Pid)], value = Value}
     || {Pid, Value} <- Series].

-define(UNFRIENDLY_CHARS, ". /").

%% TODO: identify pids in a meaningful way
-spec remote_list_to_pid(node(), string()) -> pid() | {badrpc, any()}.
remote_list_to_pid(Node, LPid) ->
    rpc:call(Node, erlang, list_to_pid, [LPid]).

-spec normalise(Name :: string()) ->
          NormalisedName :: string().
normalise(Name) when is_list(Name) ->
    [case lists:member(Char, ?UNFRIENDLY_CHARS) of
         true -> $-;
         false -> Char
     end || Char <- Name];
normalise(Name) when is_binary(Name) ->
    normalise(?b2l(Name));
normalise(Name) when is_atom(Name) ->
    normalise(?a2l(Name)).

script_src() ->
    [{probe, "process-spawn",
      [{set, spawned, [pid]}]},
     {probe, "process-exit",
      [{set, exited, [pid]}]},
     {probe, "message-send",
       [{count, sent_total, [sender_pid]}]},
     {probe, "message-send", {'<', sender_pid, receiver_pid},
      [{count, sent_up, [sender_pid, receiver_pid]}]},
     {probe, "message-send", {'>', sender_pid, receiver_pid},
      [{count, sent_down, [receiver_pid, sender_pid]}]},
     {probe, "message-send", {'==', sender_pid, receiver_pid},
      [{count, sent_self, [sender_pid]}]},
     {probe, "message-queued",
      [{count, queued, [pid]}]},
     {probe, "message-receive",
      [{count, received, [pid]}]},
     {probe, {tick, 5},
      [{print_term,
        [{spawned, '$1'},
         {exited, '$2'},
         {sent, '$3'},
         {sent_self, '$4'},
         {queued, '$5'},
         {received, '$6'},
         {sent_total, '$7'}],
        [{stat, "%s", spawned},
         {stat, "%s", exited},
         {stat, {"%s", "%s", "%@d", "%@d"}, [sent_up, sent_down]},
         {stat, {"%s", "%@d"}, sent_self},
         {stat, {"%s", "%@d"}, queued},
         {stat, {"%s", "%@d"}, received},
         {stat, {"%s", "%@d"}, sent_total}
        ]},
       {reset, spawned},
       {reset, exited},
       {reset, sent_up},
       {reset, sent_down},
       {reset, sent_self},
       {reset, queued},
       {reset, received},
       {reset, sent_total}
      ]}].
