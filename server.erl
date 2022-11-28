-module(server).

-export([start_server/0]).

-include_lib("./defs.hrl").

-spec start_server() -> _.
-spec loop(_State) -> _.
-spec do_join(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_leave(_ChatName, _ClientPID, _Ref, _State) -> _.

-spec do_new_nick(_State, _Ref, _ClientPID, _NewNick) -> _.
-spec do_client_quit(_State, _Ref, _ClientPID) -> _NewState.

start_server() ->
    catch(unregister(server)),
    register(server, self()),
    case whereis(testsuite) of
	undefined -> ok;
	TestSuitePID -> TestSuitePID!{server_up, self()}
    end,
    loop(
      #serv_st{
	 nicks = maps:new(), %% nickname map. client_pid => "nickname"
	 registrations = maps:new(), %% registration map. "chat_name" => [client_pids]
	 chatrooms = maps:new() %% chatroom map. "chat_name" => chat_pid
	}
     ).

loop(State) ->
    receive 
	%% initial connection
	{ClientPID, connect, ClientNick} ->
	    NewState =
		#serv_st{
		   nicks = maps:put(ClientPID, ClientNick, State#serv_st.nicks),
		   registrations = State#serv_st.registrations,
		   chatrooms = State#serv_st.chatrooms
		  },
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, join, ChatName} ->
	    NewState = do_join(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, leave, ChatName} ->
	    NewState = do_leave(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to register a new nickname
	{ClientPID, Ref, nick, NewNick} ->
	    NewState = do_new_nick(State, Ref, ClientPID, NewNick),
	    loop(NewState);
	%% client requests to quit
	{ClientPID, Ref, quit} ->
	    NewState = do_client_quit(State, Ref, ClientPID),
	    loop(NewState);
	{TEST_PID, get_state} ->
	    TEST_PID!{get_state, State},
	    loop(State)
    end.

%% executes join protocol from server perspective
do_join(ChatName, ClientPID, Ref, State) ->
	case maps:find(ChatName, State#serv_st.chatrooms) of
			{ok, ChatroomPID} ->
				ok;
			error ->
				ChatroomPID = spawn(chatroom, start_chatroom, [ChatName]) % ?
	end,

	ClientNick = maps:get(ClientPID, State#serv_st.nicks), %5
	ChatroomPID! {self(), Ref, register, ClientPID, ClientNick}, %6
	%7
	NewState = #serv_st{nicks = State#serv_st.nicks, registrations = maps:put(ChatName, lists:append([ClientPID], maps:get(ChatName, State#serv_st.registrations, [])), State#serv_st.registrations), chatrooms = maps:put(ChatName, ChatroomPID, State#serv_st.chatrooms)},
	NewState.

%% executes leave protocol from server perspective
do_leave(ChatName, ClientPID, Ref, State) ->
    ChatroomPID = maps:get(ChatName, State#serv_st.chatrooms), %% 4
	%%5
	NewState = #serv_st{nicks = State#serv_st.nicks, registrations = maps:update(ChatName, lists:subtract(maps:get(ChatName, State#serv_st.registrations, []), [ClientPID])), chatrooms = State#serv_st.chatrooms}, 
	%%6 [C]
	ChatroomPID!{self(), Ref, unregister, ClientPID},
	%%7 
	ClientPID!{self(), Ref, ack_leave},
	NewState.

%% executes new nickname protocol from server perspective
do_new_nick(State, _Ref, _ClientPID, _NewNick) ->
	io:format("server:do_new_nick(...): IMPLEMENT ME~n"),
	State.

%% executes client quit protocol from server perspective
do_client_quit(State, Ref, ClientPID) ->
    RemovedNicks = maps:remove(ClientPID, State#serv_st.nicks),
    lists:map(fun (name) -> case lists:member(ClientPID, maps:get(name, State#serv_st.registrations)) of
                                        true ->
                                            maps:get(name, State#serv_st.chatrooms)!{self(), Ref, unregeister, ClientPID};
                                        false ->
                                            pass
                                    end 
                  end, maps:keys(State#serv_st.registrations)),
  ClientPID!{self(), Ref, ack_quit},
  State#serv_st{nicks = RemovedNicks, registrations = registrations}.