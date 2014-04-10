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
-define(a2b(A), ?l2b(atom_to_list(A))).

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

handle_cast({send, Sample}, State = #state{}) ->
    %[Pid ! {data, Data} || Pid <- Sockets],
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
    Sample = term_to_sample(Term),
    io:format("term: ~p~n~n", [Term]).
    %io:format("sample: ~p~n", [Sample]).
    %gen_server:cast(?SERVER, {send, Sample}).

term_to_sample(Term) ->
    Term.

%handle_term(Term) ->
%    Struct = [{?a2b(Title), [to_struct(Title, Item) || Item <- Body]}
%              || {Title, [stat|Body]} <- Term],
%    JSON = lists:flatten(mochijson2:encode({struct, Struct})),
%    io:format("~s~n",[JSON]),
%    gen_server:cast(?SERVER, {send, JSON}).

%to_struct(Section, PidStr) when Section == spawned;
%                                Section == exited ->
%    ?l2b(PidStr);
%to_struct(sent, {Source, Target, Up, Down}) ->
%    {struct, [{source, ?l2b(Source)},
%              {target, ?l2b(Target)},
%              {up, Up},
%              {down, Down}]};
%to_struct(Section, {PidStr, Num}) when Section == sent_self;
%                                       Section == queued;
%                                       Section == received ->
%    {struct, [{pid, ?l2b(PidStr)},
%              {num, Num}]}.

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
