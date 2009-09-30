%%% The contents of this file are subject to the Erlang Public License,
%%% Version 1.1, (the "License"); you may not use this file except in
%%% compliance with the License. You should have received a copy of the
%%% Erlang Public License along with this software. If not, it can be
%%% retrieved via the world wide web at http://www.erlang.org/.
%%%
%%% Software distributed under the License is distributed on an "AS IS"
%%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%% the License for the specific language governing rights and limitations
%%% under the License.
%%%-------------------------------------------------------------------
%%% File:      medici_conn.erl
%%% @author    Jim McCoy <mccoy@mad-scientist.com>
%%% @copyright Copyright (c) 2009, Jim McCoy.  All Rights Reserved.
%%%
%%% @doc
%%% The medici_conn module handles a single principe connection to the Tyrant 
%%% remote database.  If is a simple gen_server that will dispatch requests
%%% to the remote database and exit if its connection to the remote database
%%% closes so that its supervisor can start another connection handler.
%%% @end
-module(medici_conn).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-include("medici.hrl").

-record(state, {socket, mod, endian, controller}).

%% @spec start_link() -> {ok,Pid} | ignore | {error,Error}
%% @private Starts the connection handler
start_link() ->
    {ok, MediciOpts} = application:get_env(medici, options),
    gen_server:start_link(?MODULE, MediciOpts, []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @spec init(Args) -> {ok, State} | {stop, Reason}
%% @private 
%% Initiates the server. Basically decides if we are talking to a remote
%% Tyrant database in table mode or hash/b-tree/fixed mode and sets the
%% server to use the appropriate principe access module for its calls.
%% @end
init(MediciOpts) ->
    {ok, Sock} = principe:connect(MediciOpts),
    case get_db_type(Sock) of
	{ok, Endian, table} ->
	    Controller = proplists:get_value(controller, MediciOpts, ?CONTROLLER_NAME),
	    Controller ! {client_start, self()},
	    process_flag(trap_exit, true),
	    {ok, #state{socket=Sock, mod=principe_table, endian=Endian, controller=Controller}};
	{ok, Endian, _} ->
	    Controller = proplists:get_value(controller, MediciOpts, ?CONTROLLER_NAME),
	    Controller ! {client_start, self()},
	    process_flag(trap_exit, true),
	    {ok, #state{socket=Sock, mod=principe, endian=Endian, controller=Controller}};
	{error, Err} ->
	    {stop, Err}
    end.

%% @spec handle_call(Request, From, State) -> {stop, Reason, State}
%% @private 
%% Handle call messages. Since none are expected (all calls should come in
%% as casts) a call message will result in termination of the server.
%% @end
handle_call(Request, _From, State) ->
    ?DEBUG_LOG("Unknown call ~p~n", [Request]),
    {stop, {unknown_call, Request}, State}.

%% @spec handle_cast(Msg, State) -> {noreply, State} | {stop, Reason, State}
%% @private Handle cast messages to forward to the remote database
handle_cast(stop, State) ->
    {stop, asked_to_stop, State};
handle_cast({From, tune}, State) ->
    %% DB tuning request will come in via this channel, but is not just passed
    %% through to principe/tyrant.  Handle it here.
    Result = tune_db(State),
    gen_server:reply(From, Result),
    {noreply, State};
handle_cast({From, CallFunc}=Request, State) when is_atom(CallFunc) ->
    Module = State#state.mod,
    Result = Module:CallFunc(State#state.socket),
    case Result of
	{error, conn_closed} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	{error, conn_error} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	_ ->
	    gen_server:reply(From, Result),
	    {noreply, State}
    end;
handle_cast({From, CallFunc, Arg1}=Request, State) when is_atom(CallFunc) ->
    Module = State#state.mod,
    Result = Module:CallFunc(State#state.socket, Arg1),
    case Result of
	{error, conn_closed} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	{error, conn_error} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	_ ->
	    gen_server:reply(From, Result),
	    {noreply, State}
    end;
handle_cast({From, CallFunc, Arg1, Arg2}=Request, State) when is_atom(CallFunc) ->
    Module = State#state.mod,
    Result = Module:CallFunc(State#state.socket, Arg1, Arg2),
    case Result of
	{error, conn_closed} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	{error, conn_error} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	_ ->
	    gen_server:reply(From, Result),
	    {noreply, State}
    end;
handle_cast({From, CallFunc, Arg1, Arg2, Arg3}=Request, State) when is_atom(CallFunc) ->
    Module = State#state.mod,
    Result = Module:CallFunc(State#state.socket, Arg1, Arg2, Arg3),
    case Result of
	{error, conn_closed} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	{error, conn_error} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	_ ->
	    gen_server:reply(From, Result),
	    {noreply, State}
    end;
handle_cast({From, CallFunc, Arg1, Arg2, Arg3, Arg4}=Request, State) when is_atom(CallFunc) ->
    Module = State#state.mod,
    Result = Module:CallFunc(State#state.socket, Arg1, Arg2, Arg3, Arg4),
    case Result of
	{error, conn_closed} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	{error, conn_error} ->
	    State#state.controller ! {retry, self(), Result, Request},
	    {stop, connection_error, State};
	_ ->
	    gen_server:reply(From, Result),
	    {noreply, State}
    end.

%% @spec handle_info(Info, State) -> {noreply, State}
%% @private Handle all non call/cast messages (none are expected).
handle_info(_Info, State) ->
    ?DEBUG_LOG("An unknown info message was received: ~w~n", [_Info]),
    %%% XXX: does this handle tcp connection closed events?
    {noreply, State}.

%% @spec terminate(Reason, State) -> void()
%% @private 
%% Server termination.  Will sync remote database, close connection, and
%% notify controller that it is shutting down.
%% @end
terminate(_Reason, State) ->
    Module = State#state.mod,
    Module:sync(State#state.socket),
    gen_tcp:close(State#state.socket),
    State#state.controller ! {client_end, self()},
    ok.

%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @private Convert process state when code is changed
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

%% @spec get_db_type(Socket::port()) -> {error, Reason::term()} |
%%                                      {ok, endian(), db_type()}
%% @type endian() = little | big
%% @type db_type() = hash | tree | fixed | table
%% @private: Query the remote end of the socket to get the remote database type
get_db_type(Socket) when is_port(Socket) ->
    StatInfo = principe:stat(Socket),
    case StatInfo of
	{error, Reason} ->
	    {error, Reason};
	StatList ->
	    case proplists:get_value(bigend, StatList) of
		"0" ->
		    Endian = little;
		_ ->
		    Endian = big
	    end,
	    case proplists:get_value(type, StatList) of
		"on-memory hash" -> 
		    Type = hash;
		"table" -> 
		    Type = table;
		"on-memory tree" -> 
		    Type = tree;
		"B+ tree" -> 
		    Type = tree;
		"hash" ->
		    Type = hash;
		"fixed-length" ->
		    Type = fixed;
		_ -> 
		    ?DEBUG_LOG("~p:get_db_type returned ~p~n", [?MODULE, proplists:get_value(type, StatList)]),
		    Type = error
	    end,
	    case Type of
		error ->
		    {error, unknown_db_type};
		_ ->
		    {ok, Endian, Type}
	    end	    
    end.

tune_db(State) ->
    StatInfo = principe:stat(State#state.socket),
    case StatInfo of
	{error, Reason} ->
	    ?DEBUG_LOG("Error getting db type for tuning: ~p", [Reason]),
	    {error, Reason};
	StatList ->
	    case proplists:get_value(type, StatList) of
		"on-memory hash" -> 
		    Records = list_to_integer(proplists:get_value(rnum, StatList)),
		    BnumInt = Records * 4,
		    TuningParam = "bnum=" ++ integer_to_list(BnumInt),
		    principe:optimize(State#state.socket, TuningParam);
		"hash" ->
		    Records = list_to_integer(proplists:get_value(rnum, StatList)),
		    BnumInt = Records * 4,
		    TuningParam = "bnum=" ++ integer_to_list(BnumInt),
		    principe:optimize(State#state.socket, TuningParam);
		Other -> 
		    ?DEBUG_LOG("Can't tune a db of type ~p yet", [Other]),
		    {error, db_type_unsupported_for_tuning}
	    end
    end.
